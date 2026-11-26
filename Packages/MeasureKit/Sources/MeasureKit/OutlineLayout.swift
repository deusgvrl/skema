import simd

/// The maths of the 3D outline box on the scan screen (A10-106, Amadeus, 21 Nov): green (#30D158), 70%, corner marks
/// with round ends, 4 pt thick at every distance (A10-121, 26 Nov: corner marks instead of dashed edges).
public enum OutlineLayout {
    /// The line's thickness on the screen, in points, at every distance.
    public static let thickness: Float = 4
    public static let opacity: Float = 0.7
    /// An arm is a quarter of its edge, but not shorter than 3 cm and not longer than 12 cm (A10-121, version 1).
    public static let cornerArmFraction: Float = 0.25
    public static let cornerArmMin: Float = 0.03
    public static let cornerArmMax: Float = 0.12
    /// The box is drawn this far (2 cm) outside the item on every side except the bottom.
    public static let boxGap: Float = 0.02

    /// A10-121 case K1: the box grown by `boxGap` on every side except the bottom (`min.y` stays on the floor).
    public static func paddedBox(_ box: WorldBox) -> WorldBox {
        WorldBox(min: SIMD3(box.min.x - boxGap, box.min.y, box.min.z - boxGap),
                 max: box.max + SIMD3(repeating: boxGap))
    }

    /// A10-121 cases K2–K5: the length of the arm on an edge of `length` metres: a quarter of it, at least
    /// `cornerArmMin`, at most `cornerArmMax`, and never more than half the edge, so two arms never cross.
    public static func armLength(ofEdge length: Float) -> Float {
        min(max(length * cornerArmFraction, cornerArmMin), cornerArmMax, length / 2)
    }

    /// A10-121 case K6: three arms at each of the box's 8 corners (24 in all), each from the corner inward along one
    /// axis, as long as `armLength` of that axis's edge.
    public static func cornerArms(of box: WorldBox) -> [WorldBox.Edge] {
        let size = box.max - box.min
        return box.corners.flatMap { corner in
            (0..<3).map { axis in
                var end = corner
                let inward: Float = corner[axis] == box.min[axis] ? 1 : -1
                end[axis] += inward * armLength(ofEdge: size[axis])
                return WorldBox.Edge(start: corner, end: end)
            }
        }
    }

    /// Case 19: the radius (metres) that makes a line `thickness` points thick on the screen, `distance` metres from
    /// the camera, with the camera's focal length in screen points: half the thickness, scaled by distance / focal.
    public static func radius(thickness: Float = thickness, distance: Float, focalLength: Float) -> Float {
        thickness / 2 * distance / focalLength
    }
}
