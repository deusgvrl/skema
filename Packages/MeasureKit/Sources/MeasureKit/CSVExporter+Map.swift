import Foundation

extension CSVExporter {
    // run_id,detector,object_id,is_subject,label,max_confidence,sightings,x_m,y_m,z_m,
    // distance_to_subject_m,height_above_floor_m,tilt_deg,aim_offset_deg,
    // true_distance_m,true_height_m,true_tilt_deg,true_aim_deg,notes
    public static let mapHeader =
        "run_id,detector,object_id,is_subject,label,max_confidence,sightings,x_m,y_m,z_m," +
        "distance_to_subject_m,height_above_floor_m,tilt_deg,aim_offset_deg," +
        "true_distance_m,true_height_m,true_tilt_deg,true_aim_deg,notes"

    /// Same formatting and escaping rules as `rows`.
    public static func mapRows(runID: String, detectorName: String, measurements: [MapMeasurement]) -> String {
        func number(_ v: Float?, _ decimals: Int) -> String {
            v.map { String(format: "%.\(decimals)f", $0) } ?? ""
        }
        return measurements.map { m in
            let o = m.object
            let cells = [
                escape(runID), escape(detectorName), String(o.id), m.isSubject ? "true" : "false",
                escape(o.label), number(o.confidence, 2), String(o.sightingCount),
                number(o.position.x, 4), number(o.position.y, 4), number(o.position.z, 4),
                number(m.distanceToSubject, 4), number(m.heightAboveFloor, 4),
                number(m.tiltDegrees, 2), number(m.aimOffsetDegrees, 2),
                "", "", "", "", "",
            ]
            return cells.joined(separator: ",") + "\n"
        }.joined()
    }
}
