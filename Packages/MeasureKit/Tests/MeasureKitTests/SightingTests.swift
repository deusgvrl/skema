import XCTest
import simd
@testable import MeasureKit

final class SightingTests: XCTestCase {
    func testUprightObjectGivesMedianPositionAndVerticalAxis() throws {
        let d = Detection(label: "light", confidence: 0.8, box: NormalizedBox(x: 0.4, y: 0, width: 0.2, height: 1))
        let s = try XCTUnwrap(Sighting.make(from: d, depth: makeFrame(depth: 2), camera: makeCamera()))
        XCTAssertEqual(s.label, "light")
        XCTAssertEqual(s.confidence, 0.8)
        XCTAssertEqual(s.pointCount, 32)
        XCTAssertTrue(near(s.position, SIMD3(0, 0, -2)))
        XCTAssertTrue(near(Geometry.tiltDegrees(axis: try XCTUnwrap(s.axis)), 0, 0.5))
    }

    func testTooFewPointsGivesNil() {
        let d = Detection(label: "light", confidence: 0.8, box: NormalizedBox(x: 0.4, y: 0, width: 0.2, height: 1))
        XCTAssertNil(Sighting.make(from: d, depth: makeFrame(depth: 2), camera: makeCamera(), minPoints: 33))
        XCTAssertNil(Sighting.make(from: d, depth: makeFrame(depth: 2, confidence: 0), camera: makeCamera()))
    }
}
