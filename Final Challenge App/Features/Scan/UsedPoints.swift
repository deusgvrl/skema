import Foundation
import MeasureKit

/// One item for the "Centres" debug view on the scan: where its top centre and base centre land (the centres the
/// results are measured from), ready to draw, with a name tag.
struct UsedPoints: Identifiable, Equatable {
    let id: UUID
    let name: String
    /// Which colour of `palette` the item is drawn in.
    let colorIndex: Int
    let topCentre: SIMD3<Float>
    /// The base centre on the floor (at the top centre's height while there is no floor).
    let baseCentre: SIMD3<Float>

    /// Item colours: the subject first, then the items in the order they were scanned.
    static let palette: [SIMD3<Float>] = [
        SIMD3(0.20, 0.78, 1.00), SIMD3(1.00, 0.60, 0.10), SIMD3(0.35, 0.85, 0.35), SIMD3(0.85, 0.40, 0.95),
        SIMD3(1.00, 0.85, 0.15), SIMD3(1.00, 0.40, 0.45)
    ]

    var color: SIMD3<Float> { Self.palette[colorIndex % Self.palette.count] }

    /// The list to draw: for every id in `order` that has both centres (the subject first).
    static func make(centres: [UUID: EquipmentCentres], names: [UUID: String], order: [UUID], subjectID: UUID,
                     floorY: Float?) -> [UsedPoints] {
        var list: [UsedPoints] = []
        for id in order {
            guard let found = centres[id], let top = found.topCentre, let base = found.baseCentre else { continue }
            list.append(UsedPoints(
                id: id, name: id == subjectID ? "Subject" : (names[id] ?? "Item"),
                colorIndex: list.count % palette.count, topCentre: top,
                baseCentre: SIMD3(base.x, floorY ?? top.y, base.y)))
        }
        return list
    }
}
