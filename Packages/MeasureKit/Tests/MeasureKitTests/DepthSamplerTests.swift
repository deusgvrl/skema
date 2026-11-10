import Testing
import simd
@testable import MeasureKit

@Suite struct DepthSamplerTests {
    @Test func principalPointMapsToMinusZ() {
        let p = DepthSampler.unproject(pixel: SIMD2(100, 50), depth: 2, camera: makeCamera())
        #expect(near(p, SIMD3(0, 0, -2)))
    }

    @Test func rightAndBelowMapsToPlusXMinusY() {
        let p = DepthSampler.unproject(pixel: SIMD2(150, 100), depth: 2, camera: makeCamera())
        #expect(near(p, SIMD3(1, -1, -2)))
    }

    @Test func honoursCameraToWorld() {
        var translated = matrix_identity_float4x4
        translated.columns.3 = SIMD4(1, 2, 3, 1)
        let a = DepthSampler.unproject(pixel: SIMD2(100, 50), depth: 2, camera: makeCamera(pose: translated))
        #expect(near(a, SIMD3(1, 2, 1)))

        // 90 degree yaw about +y: camera -z (forward) points to world -x.
        let yaw = simd_float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3(0, 1, 0)))
        let b = DepthSampler.unproject(pixel: SIMD2(100, 50), depth: 2, camera: makeCamera(pose: yaw))
        #expect(near(b, SIMD3(-2, 0, 0)))
    }

    @Test func flatWallGivesConstantZDepth() {
        let pts = DepthSampler.worldPoints(in: NormalizedBox(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
                                           depth: makeFrame(depth: 1.5), camera: makeCamera())
        #expect(!pts.isEmpty)
        #expect(pts.allSatisfy { near($0.z, -1.5) })
    }

    @Test func lowConfidenceDropped() {
        var f = makeFrame(depth: 1.5)
        var conf = f.confidence
        for i in 0..<conf.count where i % 2 == 0 { conf[i] = 1 }
        f = DepthFrame(width: f.width, height: f.height, depth: f.depth, confidence: conf)
        let box = NormalizedBox(x: 0, y: 0, width: 1, height: 1)
        let all = DepthSampler.worldPoints(in: box, depth: makeFrame(depth: 1.5), camera: makeCamera())
        let some = DepthSampler.worldPoints(in: box, depth: f, camera: makeCamera())
        #expect(some.count == all.count / 2)
        let none = DepthSampler.worldPoints(in: box, depth: makeFrame(depth: 1.5, confidence: 0), camera: makeCamera())
        #expect(none.isEmpty)
    }

    @Test func backgroundOutsideDepthBandDropped() {
        // Left 3/4 of the frame (columns 0..14) is the object at 1 m; the rest is background at 3 m.
        var depth = [Float](repeating: 3, count: 200)
        for j in 0..<10 { for i in 0..<15 { depth[j * 20 + i] = 1 } }
        let f = DepthFrame(width: 20, height: 10, depth: depth, confidence: [UInt8](repeating: 2, count: 200))
        let pts = DepthSampler.worldPoints(in: NormalizedBox(x: 0, y: 0, width: 1, height: 1),
                                           depth: f, camera: makeCamera(), inset: 0)
        #expect(!pts.isEmpty)
        #expect(pts.allSatisfy { near($0.z, -1) })
    }

    @Test func backgroundMajorityStillKeepsNearObject() {
        // Review finding 1: the object fills only 30% of the box (columns 0..5) at 1 m,
        // the wall behind fills 70% at 2.5 m. The object must win, not the wall.
        var depth = [Float](repeating: 2.5, count: 200)
        for j in 0..<10 { for i in 0..<6 { depth[j * 20 + i] = 1 } }
        let f = DepthFrame(width: 20, height: 10, depth: depth, confidence: [UInt8](repeating: 2, count: 200))
        let pts = DepthSampler.worldPoints(in: NormalizedBox(x: 0, y: 0, width: 1, height: 1),
                                           depth: f, camera: makeCamera(), inset: 0)
        #expect(pts.count == 60)
        #expect(pts.allSatisfy { near($0.z, -1) })
    }

    @Test func fewFlyingPixelsInFrontAreIgnored() {
        // Guard for the fix above: "nearest" must mean the nearest real surface,
        // not a handful of stray pixels (10 of 200) at 0.3 m.
        var depth = [Float](repeating: 1, count: 200)
        for i in 0..<10 { depth[i * 20] = 0.3 }
        let f = DepthFrame(width: 20, height: 10, depth: depth, confidence: [UInt8](repeating: 2, count: 200))
        let pts = DepthSampler.worldPoints(in: NormalizedBox(x: 0, y: 0, width: 1, height: 1),
                                           depth: f, camera: makeCamera(), inset: 0)
        #expect(pts.count == 190)
        #expect(pts.allSatisfy { near($0.z, -1) })
    }

    @Test func insetShrinksAndBadBoxGivesEmpty() {
        let box = NormalizedBox(x: 0, y: 0, width: 1, height: 1)
        let f = makeFrame(depth: 1)
        let full = DepthSampler.worldPoints(in: box, depth: f, camera: makeCamera(), inset: 0)
        let shrunk = DepthSampler.worldPoints(in: box, depth: f, camera: makeCamera(), inset: 0.25)
        #expect(full.count == 200)
        #expect(shrunk.count < full.count && !shrunk.isEmpty)
        #expect(DepthSampler.worldPoints(in: NormalizedBox(x: 0.5, y: 0.5, width: 0, height: 0),
                                         depth: f, camera: makeCamera()).isEmpty)
        #expect(DepthSampler.worldPoints(in: NormalizedBox(x: 2, y: 2, width: 0.5, height: 0.5),
                                         depth: f, camera: makeCamera()).isEmpty)
    }
}

/// A10-41 range cases. A flat wall at one depth puts every depth pixel at the same distance from the iPhone.
@Suite("Range filter (A10-41)")
struct RangeFilterTests {
    private let wholeImage = NormalizedBox(x: 0, y: 0, width: 1, height: 1)
    private let wholeMask = InstanceMask(width: 20, height: 10, pixels: [UInt8](repeating: 1, count: 200))

    private func boxPoints(wallAt depth: Float) -> [SIMD3<Float>] {
        DepthSampler.worldPoints(in: wholeImage, depth: makeFrame(depth: depth), camera: makeCamera(),
                                 inset: 0, maxRange: DepthSampler.maxRange)
    }

    private func maskPoints(wallAt depth: Float) -> [SIMD3<Float>] {
        DepthSampler.worldPoints(in: wholeMask, depth: makeFrame(depth: depth), camera: makeCamera(),
                                 erosion: 0, maxRange: DepthSampler.maxRange)
    }

    @Test("A surface 4 m away is kept")
    func nearSurfaceKept() {
        #expect(boxPoints(wallAt: 4).count == 200)
    }

    @Test("A surface 6 m away is dropped")
    func farSurfaceDropped() {
        #expect(boxPoints(wallAt: 6).isEmpty)
    }

    @Test("A surface exactly 5 m away is kept")
    func surfaceAtTheLimitKept() {
        #expect(boxPoints(wallAt: 5).count == 200)
    }

    @Test("The mask version keeps points up to exactly 5 m and drops the ones beyond")
    func maskVersionAlsoFilters() {
        #expect(maskPoints(wallAt: 4).count == 200)
        #expect(maskPoints(wallAt: 5).count == 200)
        #expect(maskPoints(wallAt: 6).isEmpty)
    }
}
