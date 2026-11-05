import XCTest
import simd
@testable import MeasureKit

private func sighting(_ x: Float, _ y: Float = 0, _ z: Float = 0,
                      axis: SIMD3<Float>? = nil, confidence: Float = 0.5) -> Sighting {
    sighting("light", x, y, z, axis: axis, confidence: confidence)
}

private func sighting(_ label: String, _ x: Float, _ y: Float = 0, _ z: Float = 0,
                      axis: SIMD3<Float>? = nil, confidence: Float = 0.5) -> Sighting {
    Sighting(label: label, confidence: confidence, position: SIMD3(x, y, z), axis: axis, pointCount: 50)
}

final class ObjectMapTests: XCTestCase {
    func testSightingsTenCentimetresApartMergeIntoOne() {
        var map = ObjectMap()
        map.add([sighting(0), sighting(0.1)])
        XCTAssertEqual(map.objects.count, 1)
        XCTAssertEqual(map.objects[0].sightingCount, 2)
        XCTAssertTrue(near(map.objects[0].position, SIMD3(0.05, 0, 0)))
    }

    func testSightingsThirtyCentimetresApartMakeTwoObjects() {
        var map = ObjectMap()
        map.add([sighting(0), sighting(0.3)])
        XCTAssertEqual(map.objects.map(\.id), [0, 1])
    }

    func testDifferentLabelAtSameSpotMakesNewObject() {
        var map = ObjectMap()
        map.add([sighting("light", 0), sighting("chair", 0)])
        XCTAssertEqual(map.objects.map(\.label), ["light", "chair"])
    }

    func testSightingMergesIntoNearestSameLabelObject() {
        var map = ObjectMap()
        map.add([sighting(0), sighting(0.3)])           // two objects at x 0 and 0.3
        map.add([sighting(0.17)])                       // within range of both; 0.13 from the second
        XCTAssertEqual(map.objects.map(\.sightingCount), [1, 2])
    }

    func testOnlyNewestSightingsFeedPosition() {
        var map = ObjectMap()
        map.add((0..<31).map { _ in sighting(0.15) })
        map.add((0..<30).map { _ in sighting(0) })
        XCTAssertEqual(map.objects.count, 1)
        XCTAssertEqual(map.objects[0].sightingCount, 61)
        XCTAssertTrue(near(map.objects[0].position, .zero))
    }

    func testOppositeAxesAverageToOneDirectionAndConfidenceIsMax() throws {
        let a = simd_normalize(SIMD3<Float>(1, 1, 0))
        var map = ObjectMap()
        map.add([sighting(0, axis: a, confidence: 0.9), sighting(0, axis: -a, confidence: 0.4)])
        let axis = try XCTUnwrap(map.objects[0].axis)
        XCTAssertTrue(near(simd_length(axis), 1))
        XCTAssertTrue(near(abs(simd_dot(axis, a)), 1))
        XCTAssertEqual(map.objects[0].confidence, 0.9)
    }

    func testObjectWithoutAxesHasNilAxis() {
        var map = ObjectMap()
        map.add([sighting(0)])
        XCTAssertNil(map.objects[0].axis)
    }

    func testIdsAreNeverReusedAfterRemoveAll() {
        var map = ObjectMap()
        map.add([sighting(0), sighting(1)])
        map.removeAll()
        XCTAssertTrue(map.objects.isEmpty)
        map.add([sighting(0)])
        XCTAssertEqual(map.objects.map(\.id), [2])
    }

    func testMeasurementsRelativeToSubject() throws {
        var map = ObjectMap()
        map.add([sighting("subject", 0), sighting("light", 3, 1, 0, axis: simd_normalize(SIMD3(0, 1, 1)))])
        let ms = map.measurements(subjectID: 0, floorY: -1)
        XCTAssertEqual(ms.count, 2)
        XCTAssertTrue(ms[0].isSubject)
        XCTAssertEqual(ms[0].distanceToSubject, 0)
        XCTAssertNil(ms[0].aimOffsetDegrees)
        XCTAssertNil(ms[0].tiltDegrees)
        XCTAssertEqual(try XCTUnwrap(ms[0].heightAboveFloor), 1, accuracy: 1e-4)
        XCTAssertFalse(ms[1].isSubject)
        XCTAssertEqual(try XCTUnwrap(ms[1].distanceToSubject), sqrt(10), accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(ms[1].heightAboveFloor), 2, accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(ms[1].tiltDegrees), 45, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(ms[1].aimOffsetDegrees), 90, accuracy: 0.01)
    }

    func testMeasurementsWithoutFloorHaveNoHeight() {
        var map = ObjectMap()
        map.add([sighting(0)])
        XCTAssertNil(map.measurements(subjectID: 0, floorY: nil)[0].heightAboveFloor)
    }

    func testNilOrUnknownSubjectGivesNilDistances() {
        var map = ObjectMap()
        map.add([sighting("a", 0), sighting("b", 3, axis: simd_normalize(SIMD3(0, 1, 1)))])
        for id in [nil, 99] as [Int?] {
            let ms = map.measurements(subjectID: id, floorY: nil)
            XCTAssertEqual(ms.count, 2)
            XCTAssertTrue(ms.allSatisfy { !$0.isSubject && $0.distanceToSubject == nil && $0.aimOffsetDegrees == nil })
            XCTAssertEqual(try XCTUnwrap(ms[1].tiltDegrees), 45, accuracy: 0.01)
        }
    }
}
