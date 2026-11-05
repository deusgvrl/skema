import Testing
import simd
@testable import MeasureKit

@Suite struct SightingMaskTests {
    @Test func usesTheMaskWhenPresent() throws {
        // Left half of the frame is at 1.0 m, right half at 1.1 m: both inside the depth band,
        // so the box version keeps both halves. The mask covers only the left half.
        var depth = [Float](repeating: 1.1, count: 200)
        for j in 0..<10 { for i in 0..<10 { depth[j * 20 + i] = 1 } }
        let frame = DepthFrame(width: 20, height: 10, depth: depth, confidence: [UInt8](repeating: 2, count: 200))
        var px = [UInt8](repeating: 0, count: 200)
        for j in 0..<10 { for i in 4...9 { px[j * 20 + i] = 1 } }
        let mask = InstanceMask(width: 20, height: 10, pixels: px)
        let box = NormalizedBox(x: 0.2, y: 0, width: 0.6, height: 1)

        let withBox = try #require(Sighting.make(from: Detection(label: "bottle", confidence: 0.9, box: box),
                                                 depth: frame, camera: makeCamera()))
        let withMask = try #require(Sighting.make(from: Detection(label: "bottle", confidence: 0.9, box: box, mask: mask),
                                                  depth: frame, camera: makeCamera()))
        #expect(near(withMask.position.z, -1))
        #expect(withMask.pointCount == 32)   // cols 5...8 x rows 1...8 after erosion
        #expect(withBox.pointCount != withMask.pointCount)
        #expect(!near(withBox.position.z, -1, 0.01))
    }
}
