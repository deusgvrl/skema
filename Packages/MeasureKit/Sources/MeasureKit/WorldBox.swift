import simd

/// A box with sides along the ARKit world axes (no room alignment), in metres.
/// A10-90 rule E made it to tell two sightings of one light apart; A10-106 uses it as a tapped light's grown box.
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

    /// True when `point` is inside the box or on its surface.
    public func contains(_ point: SIMD3<Float>) -> Bool {
        all(point .>= min) && all(point .<= max)
    }

    /// Its eight corners: bit 0 picks x, bit 1 picks y, bit 2 picks z (0 = min, 1 = max).
    public var corners: [SIMD3<Float>] {
        (0..<8).map { index in
            SIMD3(index & 1 == 0 ? min.x : max.x, index & 2 == 0 ? min.y : max.y, index & 4 == 0 ? min.z : max.z)
        }
    }

    /// A straight line in the world from `start` to `end`, in metres.
    public struct Edge: Sendable {
        public let start: SIMD3<Float>
        public let end: SIMD3<Float>

        public init(start: SIMD3<Float>, end: SIMD3<Float>) {
            self.start = start
            self.end = end
        }
    }

    /// A10-106 case 17: the box's 12 edges, each between two corners that differ on one axis (`corners` bits).
    public var edges: [Edge] {
        let corners = self.corners
        return corners.indices.flatMap { index in
            [1, 2, 4].filter { index & $0 == 0 }.map { Edge(start: corners[index], end: corners[index | $0]) }
        }
    }

    /// Linear percentile of sorted values (the same maths as numpy's default), `percent` from 0 to 100.
    private static func percentile(of sorted: [Float], _ percent: Float) -> Float {
        let position = percent / 100 * Float(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Swift.min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Float(lower))
    }
}
