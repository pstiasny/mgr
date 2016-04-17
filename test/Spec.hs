{-# LANGUAGE NamedFieldPuns #-}
import Data.Maybe (isJust, isNothing)

import Test.Hspec

import Vectors
import Rays
import Cameras
import qualified Shapes
import qualified Scene
import qualified AABBs

near :: Vec3 -> Vec3 -> Bool
near a b = len (a - b) < 0.0001

passesThrough :: Vec3 -> Ray -> Bool
passesThrough x (Ray {x0, u}) =
  let dimSel = getDimension $ maxDimension (abs u)
      t = (dimSel x - dimSel x0) / dimSel u
      tu = t @* u
  in  len (x - x0 - tu) < 0.0001

main :: IO ()
main = hspec $ do
  describe "Vector" $ do
    context "cross product" $ do
      it "forward x up yields left" $ do
        let product = (Vec3 0 0 1) `cross` (Vec3 0 1 0)
        product `shouldSatisfy` near (Vec3 (-1) 0 0)

      it "up x forward yields right" $ do
        let product = (Vec3 0 1 0) `cross` (Vec3 0 0 1)
        product `shouldSatisfy` near (Vec3 1 0 0)

      it "left x forward yields up" $ do
        let product = (Vec3 (-1) 0 0) `cross` (Vec3 0 0 1)
        product `shouldSatisfy` near (Vec3 0 1 0)

  describe "Ray" $ do
    it "should hit nearest of available collision candidates" $ do
      let n = Vec3 0 0 (-1)
          hit1 = Hit { point = unitv 1, normal = n, what = 1}
          hit2 = Hit { point = unitv 2, normal = n, what = 2}
          colliders = [
            const Nothing,
            const (Just hit2),
            const (Just hit1) ]
          ray = Ray { x0 = unitv 0, u = unitv 1 }
          (Just hit) = collideAll colliders ray
      point hit `shouldSatisfy` near (Vec3 1 1 1)
      what hit `shouldBe` 1

  describe "Camera" $ do
    let origin = Vec3 10 (-80) 124
        lookFromOrigin up dir = Camera { imW = 200, imH = 200,
                                         focalLength = 1,
                                         lookDir = dir,
                                         upDir = up,
                                         position = origin }

    context "looking forward in world space" $ do
      let c = lookFromOrigin (Vec3 0 1 0) (Vec3 0 0 1)

      it "casts rays through the middle of the imaging frame" $ do
        let r@Ray { x0, u } = computeInitialRay c 100 100
        x0 `shouldSatisfy` near origin
        u `shouldSatisfy` near (Vec3 0 0 1)
        r `shouldSatisfy` passesThrough (origin + Vec3 0 0 1)

      it "casts rays through the top left corner of the imaging frame" $ do
        let r@Ray { x0, u } = computeInitialRay c 0 0
        x0 `shouldSatisfy` near origin
        r `shouldSatisfy` passesThrough (origin + Vec3 (-0.5) (0.5) 1)

    context "looking down in world space" $ do
      let c = lookFromOrigin (Vec3 0 0 1) (Vec3 0 (-1) 0)

      it "casts rays through the middle of the imaging frame" $ do
        let Ray { x0, u } = computeInitialRay c 100 100
        x0 `shouldSatisfy` near origin
        u `shouldSatisfy` near (Vec3 0 (-1) 0)

      it "casts rays through the top left corner of the imaging frame" $ do
        let r@Ray { x0, u } = computeInitialRay c 0 0
        x0 `shouldSatisfy` near origin
        r `shouldSatisfy` passesThrough (origin + Vec3 (-0.5) (-1) 0.5)

    context "looking right in world space" $ do
      let c = lookFromOrigin (Vec3 0 1 0) (Vec3 1 0 0)

      it "casts rays through the middle of the imaging frame" $ do
        let Ray { x0, u } = computeInitialRay c 100 100
        x0 `shouldSatisfy` near origin
        u `shouldSatisfy` near (Vec3 1 0 0)

      it "casts rays through the top left corner of the imaging frame" $ do
        let r@Ray { x0, u } = computeInitialRay c 0 0
        x0 `shouldSatisfy` near origin
        r `shouldSatisfy` passesThrough (origin + Vec3 1 0.5 0.5)

  describe "Shapes" $ do
    describe "Sphere" $ do
      it "is fully bound by an AABB" $ do
        let (AABBs.BoundingBox bMin bMax) = Shapes.boundSphere 5 (Vec3 10 10 15)
        bMin `shouldSatisfy` near (Vec3 5 5 10)
        bMax `shouldSatisfy` near (Vec3 15 15 20)

    describe "Triangle" $ do
      let tc = Shapes.collideTriangle (1::Int) (Vec3 0 0 5) (Vec3 2 0 5) (Vec3 1 2 5)
          tbb = Shapes.boundTriangle (Vec3 0 0 5) (Vec3 2 0 5) (Vec3 1 2 5)

      it "reflects rays intersecting with it" $ do
        let testPoint x y = do
              let mhit = tc (Ray { x0 = Vec3 x y 0, u = Vec3 0 0 1 })
              mhit `shouldSatisfy` isJust
              let Just hit = mhit
              point hit `shouldSatisfy` near (Vec3 x y 5)
              normal hit `shouldSatisfy` near (Vec3 0 0 (-1))
              what hit `shouldBe` (1 :: Int)
        testPoint 1 1
        testPoint 0.1 0.1
        testPoint 0.9 0.1

      it "does not reflect rays not intersecting with it" $ do
        let testPoint x y = do
              let mhit = tc (Ray { x0 = Vec3 x y 0, u = Vec3 0 0 1 })
              mhit `shouldSatisfy` isNothing
        testPoint 0 1
        testPoint (-0.1) 1
        testPoint 2 1

      it "is fully bound by an AABB" $ do
        let (AABBs.BoundingBox bMin bMax) = tbb
        bMin `shouldSatisfy` near (Vec3 0 0 5)
        bMax `shouldSatisfy` near (Vec3 2 2 5)


  describe "Scene" $ do
    describe "TriangleMesh" $ do
      it "gets expanded to a list of triangles" $ do
        let tm = Scene.TriangleMesh {
                   Scene.triangleMeshPoints = [
                     Vec3 0 0 0, Vec3 0 0 1,
                     Vec3 0 1 0, Vec3 0 1 1
                     ],
                   Scene.triangleMeshTriangles = [
                     (0, 1, 2), (1, 2, 3)
                     ],
                   Scene.materialId = "fooMaterial"
                   }
            [expandedT1, expandedT2] = Scene.expand tm

        Scene.p0 expandedT1 `shouldSatisfy` near (Vec3 0 0 0)
        Scene.p1 expandedT1 `shouldSatisfy` near (Vec3 0 0 1)
        Scene.p2 expandedT1 `shouldSatisfy` near (Vec3 0 1 0)
        Scene.p0 expandedT2 `shouldSatisfy` near (Vec3 0 0 1)
        Scene.p1 expandedT2 `shouldSatisfy` near (Vec3 0 1 0)
        Scene.p2 expandedT2 `shouldSatisfy` near (Vec3 0 1 1)

        Scene.materialId expandedT1 `shouldBe` "fooMaterial"
        Scene.materialId expandedT2 `shouldBe` "fooMaterial"

  describe "AABB" $ do
    it "should bound two points" $ do
      let (AABBs.BoundingBox pMin pMax) = AABBs.fromPoints (Vec3 1 20 5)
                                                           (Vec3 14 4 3)
      pMin `shouldSatisfy` near (Vec3 1 4 3)
      pMax `shouldSatisfy` near (Vec3 14 20 5)

    it "should bound multiple points" $ do
      let bb = AABBs.BoundingBox (Vec3 1 4 3) (Vec3 14 20 5)
          (AABBs.BoundingBox pMin pMax) = AABBs.includePoint bb (Vec3 0 22 3)
      pMin `shouldSatisfy` near (Vec3 0 4 3)
      pMax `shouldSatisfy` near (Vec3 14 22 5)

    it "should bound two existing AABBs" $ do
      let bb1 = AABBs.BoundingBox (Vec3 1 4 3) (Vec3 14 20 5)
          bb2 = AABBs.BoundingBox (Vec3 0 4 2) (Vec3 15 20 1)
          (AABBs.BoundingBox pMin pMax) = AABBs.join bb1 bb2
      pMin `shouldSatisfy` near (Vec3 0 4 2)
      pMax `shouldSatisfy` near (Vec3 15 20 5)

    let bb = AABBs.BoundingBox (Vec3 10 20 30) (Vec3 20 30 40)
        collideAny = const $ Just (Hit { point = Vec3 0 0 0,
                                         normal = Vec3 0 0 (-1),
                                         what = True })
        bbc = AABBs.wrapCollider collideAny bb

    it "should not be hit by rays missing it" $ do
      bbc (Ray { x0 = Vec3 9 29 35, u = norm $ Vec3 1 1.1 0 })
        `shouldSatisfy` isNothing
      bbc (Ray { x0 = Vec3 21 29 35, u = norm $ Vec3 (-1) 1.1 0 })
        `shouldSatisfy` isNothing
      bbc (Ray { x0 = Vec3 15 19 39, u = norm $ Vec3 0 1 1.1 })
        `shouldSatisfy` isNothing

    it "should propagate rays intersecting it" $ do
      bbc (Ray { x0 = Vec3 9 29 35, u = norm $ Vec3 1 0.9 0 })
        `shouldSatisfy` isJust
      bbc (Ray { x0 = Vec3 21 29 35, u = norm $ Vec3 (-1) 0.9 0 })
        `shouldSatisfy` isJust
      bbc (Ray { x0 = Vec3 15 19 39, u = norm $ Vec3 0 1 0.9 })
        `shouldSatisfy` isJust
