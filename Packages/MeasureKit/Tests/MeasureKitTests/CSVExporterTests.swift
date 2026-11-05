import Testing
import simd
@testable import MeasureKit

@Suite struct CSVExporterTests {
    /// Minimal RFC 4180 line splitter for one record.
    private func fields(_ line: String) -> [String] {
        var out: [String] = [], cur = "", quoted = false
        var it = line.makeIterator()
        var pending: Character? = nil
        while let c = pending ?? it.next() {
            pending = nil
            if quoted {
                if c == "\"" {
                    if let n = it.next() { if n == "\"" { cur.append("\"") } else { quoted = false; pending = n } }
                    else { quoted = false }
                } else { cur.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == "," { out.append(cur); cur = "" }
            else { cur.append(c) }
        }
        out.append(cur)
        return out
    }

    private func measurement(label: String, full: Bool) -> ObjectMeasurement {
        let det = Detection(label: label, confidence: 0.85, box: NormalizedBox(x: 0, y: 0, width: 1, height: 1))
        return full
            ? ObjectMeasurement(detection: det, position: SIMD3(1, 0.5, -2), pointCount: 42, distanceToSubject: 1.25,
                                heightAboveFloor: 0.5, tiltDegrees: 12.5, aimOffsetDegrees: 30)
            : ObjectMeasurement(detection: det, position: nil, pointCount: 3, distanceToSubject: nil,
                                heightAboveFloor: nil, tiltDegrees: nil, aimOffsetDegrees: nil)
    }

    @Test func headerAndRowsHaveSameColumnCount() {
        let columns = CSVExporter.header.split(separator: ",", omittingEmptySubsequences: false)
        #expect(columns.count == 19)
        #expect(columns.first == "run_id" && columns.last == "notes")
        let text = CSVExporter.rows(runID: "r1", detectorName: "Apple Vision (saliency + classify)",
                                    measurements: [measurement(label: "cup", full: true),
                                                   measurement(label: "bottle, large", full: false)],
                                    subjectIndex: 0)
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        for line in lines { #expect(fields(line).count == columns.count) }
    }

    @Test func labelWithCommaIsQuoted() {
        let text = CSVExporter.rows(runID: "r1", detectorName: "d", measurements: [measurement(label: "bottle, large", full: true)],
                                    subjectIndex: 0)
        #expect(text.contains("\"bottle, large\""))
        #expect(fields(text.trimmingCharacters(in: .newlines))[4] == "bottle, large")
    }

    @Test func nilValuesAreEmptyCellsAndTrueColumnsStayEmpty() {
        let text = CSVExporter.rows(runID: "r1", detectorName: "d", measurements: [measurement(label: "cup", full: false)],
                                    subjectIndex: 1)
        let f = fields(text.trimmingCharacters(in: .newlines))
        #expect(f[0] == "r1" && f[1] == "d" && f[2] == "0" && f[3] == "false" && f[4] == "cup")
        #expect(f[6] == "3")
        #expect(f[7...13].allSatisfy { $0.isEmpty })   // x, y, z, distance, height, tilt, aim
        #expect(f[14...18].allSatisfy { $0.isEmpty })  // true_* and notes
    }

    @Test func valuesAreWrittenAndSubjectFlagged() {
        let text = CSVExporter.rows(runID: "r1", detectorName: "d", measurements: [measurement(label: "cup", full: true)],
                                    subjectIndex: 0)
        let f = fields(text.trimmingCharacters(in: .newlines))
        #expect(f[3] == "true")
        #expect(f[5] == "0.85")
        #expect(f[7] == "1.0000" && f[8] == "0.5000" && f[9] == "-2.0000")
        #expect(f[10] == "1.2500" && f[11] == "0.5000" && f[12] == "12.50" && f[13] == "30.00")
    }
}
