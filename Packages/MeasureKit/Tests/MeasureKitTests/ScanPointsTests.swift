import Testing
import simd
@testable import MeasureKit

@Suite struct ScanPointsTests {
    @Test func strideAndConfidenceFilter() {
        let all = DepthSampler.scanPoints(depth: makeFrame(depth: 2), camera: makeCamera(), stride: 1)
        #expect(all.count == 200)
        let strided = DepthSampler.scanPoints(depth: makeFrame(depth: 2), camera: makeCamera(), stride: 2)
        #expect(strided.count == 50)   // 10 columns x 5 rows
        #expect(DepthSampler.scanPoints(depth: makeFrame(depth: 2, confidence: 1), camera: makeCamera()).isEmpty)

        var d = makeFrame(depth: 2).depth
        d[0] = 0; d[1] = .nan
        let f = DepthFrame(width: 20, height: 10, depth: d, confidence: [UInt8](repeating: 2, count: 200))
        #expect(DepthSampler.scanPoints(depth: f, camera: makeCamera(), stride: 1).count == 198)
    }

    @Test func worldMatchesUnprojectAndUVIsPixelCentre() throws {
        let pts = DepthSampler.scanPoints(depth: makeFrame(depth: 2), camera: makeCamera(), stride: 2)
        let first = try #require(pts.first)
        #expect(near(first.uv.x, 0.5 / 20) && near(first.uv.y, 0.5 / 10))
        #expect(first.depth == 2)
        // Depth pixel (0, 0) is the image pixel (5, 5) of the 200x100 image.
        #expect(near(first.world, DepthSampler.unproject(pixel: SIMD2(5, 5), depth: 2, camera: makeCamera())))
        let second = pts[1]   // depth pixel (2, 0)
        #expect(near(second.uv.x, 2.5 / 20))
        #expect(near(second.world, DepthSampler.unproject(pixel: SIMD2(25, 5), depth: 2, camera: makeCamera())))
    }
}
