import XCTest
import simd
@testable import MeasureKit

final class CSVExporterMapTests: XCTestCase {
    private func measurement(id: Int, label: String, subject: Bool, distance: Float?, height: Float?,
                             tilt: Float?, aim: Float?) -> MapMeasurement {
        let o = MappedObject(id: id, label: label, sightingCount: 7, position: SIMD3(1, 2, 3),
                             axis: nil, confidence: 0.876)
        return MapMeasurement(object: o, isSubject: subject, distanceToSubject: distance,
                              heightAboveFloor: height, tiltDegrees: tilt, aimOffsetDegrees: aim)
    }

    func testRowsMatchHeaderColumnsFlagSubjectAndLeaveNilsEmpty() {
        let ms = [
            measurement(id: 0, label: "person", subject: true, distance: 0, height: 1.5, tilt: nil, aim: nil),
            measurement(id: 3, label: "lamp, \"big\"", subject: false, distance: 1.23456, height: nil, tilt: 45.678, aim: 12.3),
        ]
        let csv = CSVExporter.mapRows(runID: "r1", detectorName: "vision", measurements: ms)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        XCTAssertTrue(csv.hasSuffix("\n"))
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(CSVExporter.mapHeader.split(separator: ",", omittingEmptySubsequences: false).count, 19)
        XCTAssertTrue(CSVExporter.mapHeader.hasPrefix("run_id,detector,object_id,is_subject,label,max_confidence,sightings,"))
        XCTAssertEqual(lines[0], "r1,vision,0,true,person,0.88,7,1.0000,2.0000,3.0000,0.0000,1.5000,,,,,,,")
        XCTAssertEqual(lines[1], "r1,vision,3,false,\"lamp, \"\"big\"\"\",0.88,7,1.0000,2.0000,3.0000,1.2346,,45.68,12.30,,,,,")
        // quoted cells contain a comma, so count columns on the unquoted row
        XCTAssertEqual(lines[0].split(separator: ",", omittingEmptySubsequences: false).count, 19)
    }
}
