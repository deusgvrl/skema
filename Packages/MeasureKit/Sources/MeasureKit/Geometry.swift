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
    /// Averaging only this slice gives where the subject stands. Example: for a bottle, the points from 0 to 10 cm.
    public static let baseBandHeight: Float = 0.10

    /// The top is the height that this many percent of the points lie under (98 = the 98th percentile), not the single highest point.
    public static let topPercentile = 98

    /// For `CentreRule.middle`: the share of points dropped at each end of each axis (0.02 = the lowest 2% and the highest 2%)
    /// before the extremes are taken, so a stray pixel or a hand cannot stretch the middle.
    public static let middleTrim: Float = 0.02

    /// For `CentreRule.middle`: the head of a light is the wide part of its points. The points are cut into layers this
    /// thick (metres) and each layer's horizontal width is measured.
    public static let middleLayer: Float = 0.02

    /// For `CentreRule.middle`: a layer is part of the head while it is at least this share as wide as the widest layer.
    /// A stand (a few cm) next to a head (20 cm or more) is cut off.
    public static let middleMinWidthShare: Float = 0.5

    /// For `CentreRule.middle`: a layer needs this many points to have a width, and the head this many in all,
    /// otherwise every point counts.
    public static let middleMinLayerPoints = 5
    public static let middleMinHeadPoints = 20

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
    /// y says how high. The top centre (x, y, z) is the highest part of the points: the lighting point of a light or
    /// the camera body. For equipment the base centre is the top centre's x and z (team decision, 11 Nov 2026: the
    /// position of the light head or camera counts, not the stand), so the equipment does not need to touch the floor.
    /// The subject (`isSubject`) is a product: its base centre is the bottom of its points, which can be on a table.
    /// When the equipment cannot be measured, the result says why (`status`) and has no centres.
    /// `outOfRange` is not decided here: it needs the whole scan, see `EquipmentPoints.scanResult(isSubject:)`.
    ///
    /// `rule` says how the top centre of equipment (not the subject) is found: `.topPoint` as above, or `.middle`: the
    /// centre of the points' 3D extents (the middle of a light's head), with its base centre straight under it.
    public static func centres(
        of points: [SIMD3<Float>], isSubject: Bool, rule: CentreRule = .topPoint
    ) -> EquipmentCentres {
        // Too few points means too little information to trust a base or a top.
        // `lowest` is the height of the lowest point.
        guard points.count >= minPointCount, let lowest = points.map(\.y).min() else {
            return EquipmentCentres(status: .tooFewPoints, baseCentre: nil, topCentre: nil)
        }

        // The middle of the head: the centre of the extents on each axis, after trimming the strays at both ends.
        if rule == .middle, !isSubject {
            let head = headPoints(of: points, lowest: lowest)
            let middle = SIMD3(trimmedMidpoint(head.map(\.x)), trimmedMidpoint(head.map(\.y)),
                               trimmedMidpoint(head.map(\.z)))
            return EquipmentCentres(status: .measured, baseCentre: SIMD2(middle.x, middle.z), topCentre: middle)
        }

        // Top height. Use a high percentile, not the highest point,
        // so a few stray points cannot make the equipment look taller.
        let topY = percentile(points.map(\.y), topPercentile)

        // Top centre x and z. Average a thin slice of points just under the top height: one point would be noisy.
        // The slice also stops at the top height, because the points above it are the strays we just chose to ignore.
        let slice = points.filter { $0.y >= topY - topEpsilon && $0.y <= topY }
        let topXZ = meanXZ(slice)

        // Base centre. Equipment: straight under the top. Subject: a thin band of points just above the lowest point
        // (a band, not the single lowest point, because one point is noisy).
        let baseCentre = isSubject ? meanXZ(points.filter { $0.y <= lowest + baseBandHeight }) : topXZ

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

    /// The wide part of a light's points, without its stand: cut the points into layers of `middleLayer`, measure each
    /// layer's horizontal width, and keep the layers around the widest one that are at least `middleMinWidthShare` as
    /// wide. Every point when no layer has a width or the head would have fewer than `middleMinHeadPoints` points.
    private static func headPoints(of points: [SIMD3<Float>], lowest: Float) -> [SIMD3<Float>] {
        var layers: [Int: [SIMD3<Float>]] = [:]
        for point in points {
            layers[Int(((point.y - lowest) / middleLayer).rounded(.down)), default: []].append(point)
        }
        var widths: [Int: Float] = [:]
        for (layer, members) in layers where members.count >= middleMinLayerPoints {
            widths[layer] = hypot(trimmedSpan(members.map(\.x)), trimmedSpan(members.map(\.z)))
        }
        guard let widest = widths.keys.sorted().max(by: { widths[$0, default: 0] < widths[$1, default: 0] }),
              let widestWidth = widths[widest], widestWidth > 0 else { return points }
        let minimum = widestWidth * middleMinWidthShare
        // Grow from the widest layer, bridging one empty or sparse layer (LiDAR leaves holes), so a gap does not cut it.
        // A missing layer is never wide, even when the share is set to 0, so the growth always ends.
        func wide(_ layer: Int) -> Bool { widths[layer].map { $0 > 0 && $0 >= minimum } ?? false }
        var low = widest, high = widest
        while wide(low - 1) || wide(low - 2) { low -= wide(low - 1) ? 1 : 2 }
        while wide(high + 1) || wide(high + 2) { high += wide(high + 1) ? 1 : 2 }
        let head = layers.filter { (low...high).contains($0.key) }.flatMap(\.value)
        return head.count >= middleMinHeadPoints ? head : points
    }

    /// The distance between the smallest and the largest value, after dropping the lowest and highest `middleTrim` share.
    private static func trimmedSpan(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        let dropped = Int(Float(sorted.count) * middleTrim)
        return sorted[sorted.count - 1 - dropped] - sorted[dropped]
    }

    /// The midpoint between the smallest and the largest value, after dropping the lowest and highest `middleTrim` share.
    private static func trimmedMidpoint(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        let dropped = Int(Float(sorted.count) * middleTrim)
        return (sorted[dropped] + sorted[sorted.count - 1 - dropped]) / 2
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
