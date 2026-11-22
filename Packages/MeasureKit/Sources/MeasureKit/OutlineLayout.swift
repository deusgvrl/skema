import simd

/// The maths of the 3D outline box on the scan screen (A10-106, Amadeus, 21 Nov): white, 70%, dashed, round ends,
/// 4 pt thick at every distance.
public enum OutlineLayout {
    /// One dash and one gap along an edge, in metres.
    public static let dash: Float = 0.06
    public static let gap: Float = 0.04
    /// The line's thickness on the screen, in points, at every distance.
    public static let thickness: Float = 4
    public static let opacity: Float = 0.7
    /// A dash shorter than this (1 mm) is not drawn.
    static let minimumDash: Float = 0.001

    /// Case 18: the dashes along the line from `start` to `end`: `dash` long, `gap` apart, from `start` on.
    /// The last dash is cut at `end`.
    public static func dashes(from start: SIMD3<Float>, to end: SIMD3<Float>, dash: Float = dash,
                              gap: Float = gap) -> [WorldBox.Edge] {
        let length = simd_distance(start, end)
        guard length > 0, dash > 0 else { return [] }
        let direction = (end - start) / length
        // Stop just before the end: float rounding can put a last dash of almost no length right at the end.
        return stride(from: Float(0), to: length - minimumDash, by: dash + gap).map { offset in
            WorldBox.Edge(start: start + direction * offset, end: start + direction * min(offset + dash, length))
        }
    }

    /// Case 19: the radius (metres) that makes a line `thickness` points thick on the screen, `distance` metres from
    /// the camera, with the camera's focal length in screen points: half the thickness, scaled by distance / focal.
    public static func radius(thickness: Float = thickness, distance: Float, focalLength: Float) -> Float {
        thickness / 2 * distance / focalLength
    }
}
