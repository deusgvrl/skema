import simd

/// A box with sides along the ARKit world axes (no room alignment), in metres.
/// Tracking (A10-90, rule E) uses it to tell whether two sightings show the same light.
public struct WorldBox: Equatable, Sendable {
    public let min: SIMD3<Float>
    public let max: SIMD3<Float>

    /// Every side is at least this long (2 cm): a flat object would otherwise get a box with no volume.
    public static let minSide: Float = 0.02
    /// The box ignores the most extreme 2% of the points on each side, so a few stray depth pixels
    /// do not stretch it (Cases D24–D25).
    public static let lowPercentile: Float = 2
    public static let highPercentile: Float = 98

    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }

    public var volume: Float {
        let size = max - min
        return size.x * size.y * size.z
    }

    /// Cases D24–D26: per axis from the 2nd to the 98th percentile of the points;
    /// a side shorter than `minSide` is widened to it, centred on the same middle. Nil for no points.
    public static func around(_ points: [SIMD3<Float>]) -> WorldBox? {
        guard !points.isEmpty else { return nil }
        var low = SIMD3<Float>.zero
        var high = SIMD3<Float>.zero
        for axis in 0..<3 {
            let values = points.map { $0[axis] }.sorted()
            low[axis] = percentile(of: values, lowPercentile)
            high[axis] = percentile(of: values, highPercentile)
            if high[axis] - low[axis] < minSide {
                let middle = (low[axis] + high[axis]) / 2
                low[axis] = middle - minSide / 2
                high[axis] = middle + minSide / 2
            }
        }
        return WorldBox(min: low, max: high)
    }

    /// Both boxes grown to hold each other (min of the mins, max of the maxes). Case D28.
    public func union(_ other: WorldBox) -> WorldBox {
        WorldBox(min: simd_min(min, other.min), max: simd_max(max, other.max))
    }

    /// Cases D30–D33: the volume the two boxes share, divided by the volume of the SMALLER box.
    /// 1 is fully inside, 0 is not touching.
    public func shareInside(_ other: WorldBox) -> Float {
        let overlap = simd_max(simd_min(max, other.max) - simd_max(min, other.min), .zero)
        let shared = overlap.x * overlap.y * overlap.z
        let smaller = Swift.min(volume, other.volume)
        return smaller > 0 ? shared / smaller : 0
    }

    /// Linear percentile of sorted values (the same maths as numpy's default), `percent` from 0 to 100.
    private static func percentile(of sorted: [Float], _ percent: Float) -> Float {
        let position = percent / 100 * Float(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Swift.min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Float(lower))
    }
}
