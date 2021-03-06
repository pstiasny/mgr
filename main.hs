{-# LANGUAGE NamedFieldPuns #-}

import System.Console.ArgParser (parsedBy, andBy, reqPos, optFlag, withParseResult)
import Control.Concurrent (getNumCapabilities)
import Control.DeepSeq (force)
import Control.Monad (forM_)
import Control.Parallel.Strategies (Eval, rpar, runEval)
import Control.Monad.Par (runPar, spawn, get)
import Data.Map (Map, fromList, (!))
import Data.Tuple (swap)
import qualified Data.Vector as V
import qualified Data.Vector.Mutable as MV
import System.Environment
import Codec.Picture

import Vectors
import Rays
import qualified Scene as S
import Shapes
import Cameras
import Shaders
import Culling
import AABBs (BoundingBox)
import Integrators (radiance)
import Sampling (lineBatches, squareBatches)


data Invocation = Invocation
  { invInput :: String
  , invOutput :: String
  , invParMode :: String
  }


invocationParser = Invocation
  `parsedBy` reqPos "input"
  `andBy` reqPos "output"
  `andBy` optFlag "sequential" "parallel-mode"


buildCollisionModel :: S.Scene -> [(BoundingBox, Collider Material)]
buildCollisionModel s = zip sceneObjBounds sceneColliders
  where
    sceneObjects = S.objects s >>= S.expand

    sceneColliders = map collideSceneObject sceneObjects
    collideSceneObject (S.Sphere p r mId) = collideSphere (mat mId) r p
    collideSceneObject (S.Triangle p0 p1 p2 n0 n1 n2 mId) =
      collideTriangle (mat mId) p0 p1 p2 n0 n1 n2

    sceneObjBounds = map boundSceneObject sceneObjects
    boundSceneObject (S.Sphere p r mId) = boundSphere r p
    boundSceneObject (S.Triangle {S.p0, S.p1, S.p2, S.materialId=mId}) = boundTriangle p0 p1 p2

    mat mId = Material (mats ! mId)
    mats :: Map String Shader
    mats = fromList [(S.id m, shaderFromDescription m) | m <- S.materials s]
    shaderFromDescription desc = case desc of
      S.BlinnPhongMaterial id ambient diffuse specular shininess ->
        blinnPhong ambient diffuse specular shininess

spectrumToPixel :: Spectrum -> PixelRGBF
spectrumToPixel (Vec3 r g b) = PixelRGBF r g b

type SampleCoordinates = (Int, Int)
type Sample = (SampleCoordinates, Spectrum)

render :: Int -> Int -> [[SampleCoordinates]] ->
          (Float -> Float -> Ray) -> (Ray -> Spectrum) ->
          [Sample]
render w h batches cast li = concat $ map (map sample) batches
  where
    sample (u, v) = ((u, v), li $ cast (fromIntegral u) (fromIntegral v))

renderEval :: Int -> Int -> [[SampleCoordinates]] ->
              (Float -> Float -> Ray) -> (Ray -> Spectrum) ->
              [Sample]
renderEval w h batches cast li =
  let batch coords = [ ((u, v), li (cast (fromIntegral u) (fromIntegral v)))
                     | (u, v) <- coords ]
      evals :: [Eval [Sample]]
      evals = [ rpar (force (batch coords)) | coords <- batches ]
  in  concat $ runEval $ sequence evals


renderPar :: Int -> Int -> [[SampleCoordinates]] ->
             (Float -> Float -> Ray) -> (Ray -> Spectrum) ->
             [Sample]
renderPar w h batches cast li =
  let batch coords = [ ((u, v), li (cast (fromIntegral u) (fromIntegral v)))
                     | (u, v) <- coords ]
      par = do
        ivars <- mapM (spawn . return . batch) batches
        pixelBatches <- mapM get ivars
        return $ concat pixelBatches
  in  runPar par

samplesToImage :: Int -> Int -> [Sample] -> Image PixelRGBF
samplesToImage w h samples =
  let uvToIndex u v = w * v + u
      image = V.create $ do
        img <- MV.new (w * h)
        forM_ samples $ \((u, v), spectrum) ->
          MV.write img (uvToIndex u v) spectrum
        return img
      getPixel u v = spectrumToPixel $ image V.! (uvToIndex u v)
  in  generateImage getPixel w h

roundUpPow2 :: Int -> Int
roundUpPow2 x = 2 ^ (ceiling (logBase 2 (fromIntegral x)))

app invocation = do
  numThreads <- getNumCapabilities

  sceneFile <- readFile (invInput invocation)

  let scene = read sceneFile :: S.Scene
      collider = cull (S.cullingMode scene) (buildCollisionModel scene)

      camera = S.camera scene
      caster = computeInitialRay camera
      width = floor $ imW camera
      height = floor $ imH camera

      li :: Ray -> Spectrum
      li = radiance (S.integrator scene) (S.lights scene) collider

      nBatches = roundUpPow2 $ max
        (32 * numThreads)
        width * height `div` (16 * 16)
      samplePoints = squareBatches width height nBatches

      samples =
        case (invParMode invocation) of
          "sequential" -> render width height samplePoints caster li
          "eval" -> renderEval width height samplePoints caster li
          "par" -> renderPar width height samplePoints caster li
      img = samplesToImage width height samples

  putStrLn $ (show numThreads) ++ " threads, " ++ (show nBatches) ++
             " batches, parallel " ++ (invParMode invocation)
  savePngImage (invOutput invocation) (ImageRGBF img)


main = withParseResult invocationParser app
