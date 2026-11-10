import Foundation
import simd

/// Pure maths on world-space points (y up).
public enum Geometry {
    /// The principal axis needs its largest eigenvalue to be at least this many times the second one.
    /// Below that, the points have no dominant direction (blob, disc, square) and the axis is nil.
    public static let dominanceRatio: Float = 1.5

    /// Below this tilt the axis's horizontal direction is LiDAR noise, so there is no aim.
    public static let minAimTiltDegrees: Float = 20

    /// Below this many points the equipment is "too few points".
    public static let minPointCount = 100

    /// Height of the "base band": the thin slice of points from the lowest point up to this much higher.
    /// Averaging only this slice gives where the equipment stands. Example: for the stand, the points from 0 to 10 cm.
    public static let baseBandHeight: Float = 0.10

    /// If the lowest point is higher than this above the floor, the base is not on the floor
    public static let maxBaseGapAboveFloor: Float = 0.15

    /// The top is the height that this many percent of the points lie under (98 = the 98th percentile), not the single highest point.
    public static let topPercentile = 98

    /// Thickness of the "top slice": the points from the top height down to this much lower give the top centre's x and z.
    public static let topEpsilon: Float = 0.05

    /// Per-axis median. Nil when `points` is empty.
    public static func medianPoint(_ points: [SIMD3<Float>]) -> SIMD3<Float>? {
        guard !points.isEmpty else { return nil }
        func median(_ values: [Float]) -> Float {
            let s = values.sorted()
            let n = s.count
            return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
        }
        return SIMD3(median(points.map(\.x)), median(points.map(\.y)), median(points.map(\.z)))
    }

    /// Unit direction of largest variance (PCA), flipped so y >= 0.
    /// Nil for fewer than 3 points or when the largest eigenvalue is less than `dominanceRatio` times the second.
    public static func principalAxis(_ points: [SIMD3<Float>]) -> SIMD3<Float>? {
        guard points.count >= 3 else { return nil }
        let mean = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
        var cov = simd_float3x3(0)
        for p in points {
            let d = p - mean
            cov += simd_float3x3(columns: (d * d.x, d * d.y, d * d.z))
        }
        cov = cov * (1 / Float(points.count))

        guard let (l1, v1) = dominantEigen(cov), l1 > 1e-12 else { return nil }
        let deflated = cov - simd_float3x3(columns: (v1 * (l1 * v1.x), v1 * (l1 * v1.y), v1 * (l1 * v1.z)))
        let l2 = dominantEigen(deflated)?.0 ?? 0
        guard l1 >= dominanceRatio * max(l2, 0) else { return nil }

        var axis = v1
        if axis.y < 0 || (axis.y == 0 && (axis.x < 0 || (axis.x == 0 && axis.z < 0))) { axis = -axis }
        return axis
    }

    /// Angle between the axis line and vertical: 0 upright ... 90 flat. The sign of the axis does not matter.
    public static func tiltDegrees(axis: SIMD3<Float>) -> Float {
        let len = simd_length(axis)
        guard len > 0 else { return 0 }
        return acos(min(1, abs(axis.y) / len)) * 180 / .pi
    }

    /// Horizontal (xz) angle between the axis LINE and the line from `from` to `to`, folded to 0...90.
    /// Nil when the axis tilts less than `minAimTiltDegrees` from vertical
    /// or `to` is straight above/below `from`.
    public static func aimOffsetDegrees(axis: SIMD3<Float>, from: SIMD3<Float>, to: SIMD3<Float>) -> Float? {
        let len = simd_length(axis)
        guard len > 0 else { return nil }
        let a = SIMD2<Float>(axis.x, axis.z) / len
        let d = SIMD2<Float>(to.x - from.x, to.z - from.z)
        let aLen = simd_length(a), dLen = simd_length(d)
        guard aLen >= sin(minAimTiltDegrees * .pi / 180), dLen > 1e-6 else { return nil }
        let cosine = min(1, abs(simd_dot(a, d)) / (aLen * dLen))
        return acos(cosine) * 180 / .pi
    }

    /// Height of `point` above the horizontal floor plane at `floorY`.
    public static func heightAboveFloor(_ point: SIMD3<Float>, floorY: Float) -> Float {
        point.y - floorY
    }

    /// Base centre and top centre of one piece of equipment from its world points (metres, y up).
    ///
    /// `points` are the 3D dots the LiDAR scan put on this equipment: x and z say where it is on the floor,
    /// y says how high. The base centre (x, z) is where the equipment stands. The top centre (x, y, z) is its highest part.
    /// The subject (`isSubject`) skips the floor rule because the product often sits on a table.
    /// When the equipment cannot be measured, the result says why (`status`) and has no centres.
    /// `outOfRange` is not decided here: it needs the whole scan, see `EquipmentPoints.scanResult(floorY:isSubject:)`.
    public static func centres(of points: [SIMD3<Float>], floorY: Float, isSubject: Bool) -> EquipmentCentres {
        // Small helper for every "cannot measure" exit: a status with no centres.
        func notMeasured(_ status: MeasurementStatus) -> EquipmentCentres {
            EquipmentCentres(status: status, baseCentre: nil, topCentre: nil)
        }

        // Step 1: too few points means too little information to trust a base or a top. `lowest` is the height of the lowest point.
        guard points.count >= minPointCount, let lowest = points.map(\.y).min() else {
            return notMeasured(.tooFewPoints)
        }

        // Step 2: a normal piece of equipment must touch the floor. If its lowest point is well above the floor,
        // the base was not seen. The subject is exempt: its base is the bottom of the product, which can sit on a table.
        if !isSubject, lowest - floorY > maxBaseGapAboveFloor {
            return notMeasured(.baseNotSeen)
        }

        // Step 3: base centre. Take only a thin band of points just above the lowest point and average their x and z.
        // A band, not the single lowest point, because one point is noisy.
        let band = points.filter { $0.y <= lowest + baseBandHeight }
        let baseCentre = meanXZ(band)

        // Step 4: top height. Use a high percentile, not the highest point, so a few stray points cannot make the equipment look taller.
        let topY = percentile(points.map(\.y), topPercentile)

        // Step 5: top centre x and z. Average a thin slice of points just under the top height: one point would be noisy.
        // The slice also stops at the top height, because the points above it are the strays we just chose to ignore.
        let slice = points.filter { $0.y >= topY - topEpsilon && $0.y <= topY }
        let topXZ = meanXZ(slice)

        // Done: measured, with the base centre (x, z) and the top centre (x, y, z). The top's height is the percentile.
        return EquipmentCentres(status: .measured, baseCentre: baseCentre, topCentre: SIMD3(topXZ.x, topY, topXZ.y))
    }

    /// Returns the distance on the floor, in metres, between the base centres of two pieces of equipment.
    ///
    /// Only x and z count, so height is ignored. Returns nil when either base centre is missing (not measured).
    public static func floorDistance(from subject: EquipmentCentres, to equipment: EquipmentCentres) -> Float? {
        guard let subjectBase = subject.baseCentre, let equipmentBase = equipment.baseCentre else { return nil }
        return simd_distance(subjectBase, equipmentBase)
    }

    /// Returns the height of a piece of equipment above the floor, in metres: top centre's y minus the floor height.
    ///
    /// Returns nil when there is no floor height or no top centre (not measured).
    public static func height(of equipment: EquipmentCentres, floorY: Float?) -> Float? {
        guard let topCentre = equipment.topCentre, let floorY else { return nil }
        return heightAboveFloor(topCentre, floorY: floorY)
    }
    
    /// Returns where a piece of equipment stands on the floor relative to the subject, in metres.
    ///
    /// The result is the equipment's base centre minus the subject's base centre: x is the world x difference,
    /// y holds the world z difference (a `SIMD2` has no z slot). Heights are ignored.
    /// Returns nil when either base centre is missing.
    public static func floorOffset(of equipment: EquipmentCentres, from subject: EquipmentCentres) -> SIMD2<Float>? {
        guard let subjectBase = subject.baseCentre, let equipmentBase = equipment.baseCentre else { return nil }
        return equipmentBase - subjectBase
    }

    /// The average position on the floor of some points: add up all the x values and all the z values, then divide by how many there are.
    private static func meanXZ(_ points: [SIMD3<Float>]) -> SIMD2<Float> {
        // `reduce` walks through the points and keeps a running total of (x, z); `$0` is the total so far, `$1` the next point.
        let sum = points.reduce(SIMD2<Float>.zero) { $0 + SIMD2($1.x, $1.z) }
        return sum / Float(points.count)
    }

    /// Nearest-rank percentile: sort the values from low to high and take the one at rank `ceil(percent * n / 100)`.
    private static func percentile(_ values: [Float], _ percent: Int) -> Float {
        let sorted = values.sorted()
        // Whole numbers only: `(a + 99) / 100` is `a / 100` rounded up, with no floating-point rounding error.
        let rank = (percent * sorted.count + 99) / 100
        // `min` and `max` keep the position inside the array.
        return sorted[min(sorted.count - 1, max(0, rank - 1))]
    }

    /// Largest eigenvalue and unit eigenvector of a symmetric positive semi-definite matrix, by power iteration.
    private static func dominantEigen(_ m: simd_float3x3) -> (Float, SIMD3<Float>)? {
        // Start from the longest column: it lies in the matrix's range, so it is never orthogonal to the dominant vector.
        guard var v = [m.columns.0, m.columns.1, m.columns.2].max(by: { simd_length($0) < simd_length($1) }), simd_length(v) > 1e-20 else { return nil }
        v = simd_normalize(v)
        for _ in 0..<200 {
            let w = m * v
            let n = simd_length(w)
            guard n > 1e-20 else { return (0, v) }
            v = w / n
        }
        return (simd_dot(v, m * v), v)
    }
}

extension Geometry {
    public static let uprightToleranceDegrees: Float = 10
}
