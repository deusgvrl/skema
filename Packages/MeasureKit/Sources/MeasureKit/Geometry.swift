import Foundation
import simd

/// Pure maths on world-space points (y up).
public enum Geometry {
    /// The principal axis needs its largest eigenvalue to be at least this many times the second one.
    /// Below that, the points have no dominant direction (blob, disc, square) and the axis is nil.
    public static let dominanceRatio: Float = 1.5

    /// Below this tilt the axis's horizontal direction is LiDAR noise, so there is no aim.
    public static let minAimTiltDegrees: Float = 20

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
