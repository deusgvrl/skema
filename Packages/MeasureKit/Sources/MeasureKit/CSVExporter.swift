import Foundation

/// Writes measurements as CSV for comparing with a tape measure.
public enum CSVExporter {
    public static let header =
        "run_id,detector,index,is_subject,label,confidence,point_count,x_m,y_m,z_m," +
        "distance_to_subject_m,height_above_floor_m,tilt_deg,aim_offset_deg," +
        "true_distance_m,true_height_m,true_tilt_deg,true_aim_deg,notes"

    /// One line per measurement, each ending in "\n", without the header.
    /// The true_* and notes columns stay empty: a person fills them from a tape measure.
    /// Metres use 4 decimals, degrees 2, confidence 2. Nil values are empty cells.
    public static func rows(runID: String, detectorName: String,
                            measurements: [ObjectMeasurement], subjectIndex: Int) -> String {
        func number(_ v: Float?, _ decimals: Int) -> String {
            v.map { String(format: "%.\(decimals)f", $0) } ?? ""
        }
        return measurements.enumerated().map { index, m in
            let cells = [
                escape(runID), escape(detectorName), String(index), index == subjectIndex ? "true" : "false",
                escape(m.detection.label), number(m.detection.confidence, 2), String(m.pointCount),
                number(m.position?.x, 4), number(m.position?.y, 4), number(m.position?.z, 4),
                number(m.distanceToSubject, 4), number(m.heightAboveFloor, 4),
                number(m.tiltDegrees, 2), number(m.aimOffsetDegrees, 2),
                "", "", "", "", "",
            ]
            return cells.joined(separator: ",") + "\n"
        }.joined()
    }

    /// RFC 4180: quote fields with a comma, quote or newline; double any quotes inside.
    static func escape(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
