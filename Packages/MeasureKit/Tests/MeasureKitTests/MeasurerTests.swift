import Testing
import simd
@testable import MeasureKit

@Suite struct MeasurerTests {
    /// 20x10 frame: object A (1 m) in columns 0...8, object B (2 m) in columns 11...19, nothing elsewhere.
    private func twoObjectFrame() -> DepthFrame {
        var depth = [Float](repeating: 0, count: 200)
        for j in 0..<10 {
            for i in 0...8 { depth[j * 20 + i] = 1 }
            for i in 11...19 { depth[j * 20 + i] = 2 }
        }
        return DepthFrame(width: 20, height: 10, depth: depth, confidence: [UInt8](repeating: 2, count: 200))
    }

    private let boxA = NormalizedBox(x: 0, y: 0, width: 0.5, height: 1)
    private let boxB = NormalizedBox(x: 0.55, y: 0, width: 0.45, height: 1)

    @Test func twoObjectsGetRightDistanceAndSubjectIsZero() {
        let dets = [Detection(label: "bottle", confidence: 0.9, box: boxA),
                    Detection(label: "cup", confidence: 0.8, box: boxB)]
        let out = Measurer().measure(detections: dets, subjectIndex: 0, depth: twoObjectFrame(),
                                     camera: makeCamera(), floorY: -0.5)
        #expect(out.count == 2)
        #expect(out[0].detection == dets[0] && out[1].detection == dets[1])
        // A at (-0.5, 0, -1), B at (1.1, 0, -2).
        #expect(near(out[0].position!, SIMD3(-0.5, 0, -1)))
        #expect(near(out[1].position!, SIMD3(1.1, 0, -2)))
        #expect(out[0].distanceToSubject == 0)
        #expect(near(out[1].distanceToSubject!, (1.6 * 1.6 + 1).squareRoot()))
        #expect(near(out[0].heightAboveFloor!, 0.5))
    }

    @Test func tooFewPointsGivesNilValuesButKeepsPointCount() {
        // Tiny box: 4x4 depth pixels after the default inset, below minPoints = 20.
        let sparse = Detection(label: "cup", confidence: 0.7, box: NormalizedBox(x: 0, y: 0, width: 0.2, height: 0.4))
        let good = Detection(label: "bottle", confidence: 0.9, box: boxA)
        let frame = twoObjectFrame()

        let a = Measurer().measure(detections: [good, sparse], subjectIndex: 0, depth: frame,
                                   camera: makeCamera(), floorY: nil)
        #expect(a[1].pointCount == 16)
        #expect(a[1].position == nil && a[1].distanceToSubject == nil)
        #expect(a[1].heightAboveFloor == nil && a[1].tiltDegrees == nil && a[1].aimOffsetDegrees == nil)
        #expect(a[0].heightAboveFloor == nil)  // no floor found

        // Subject without a position: every distance is nil, but positions of the others stay.
        let b = Measurer().measure(detections: [good, sparse], subjectIndex: 1, depth: frame,
                                   camera: makeCamera(), floorY: nil)
        #expect(b.allSatisfy { $0.distanceToSubject == nil })
        #expect(b[0].position != nil)
    }
}
