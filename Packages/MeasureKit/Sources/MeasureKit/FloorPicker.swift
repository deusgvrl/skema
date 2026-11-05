/// A horizontal plane ARKit found, copied out of `ARPlaneAnchor` so the choice runs without ARKit.
public struct HorizontalPlane: Equatable, Sendable {
    /// World y of the plane (metres, y up).
    public let y: Float
    /// ARKit classified it as `.floor`.
    public let isFloor: Bool

    public init(y: Float, isFloor: Bool) {
        self.y = y
        self.isFloor = isFloor
    }
}

/// Picks the floor height for `heightAboveFloor`.
public enum FloorPicker {
    /// Lowest plane classified as floor. Nil when there is none: a desk or shelf never stands in for the floor,
    /// because a height measured from it would look right and be wrong.
    public static func floorY(_ planes: [HorizontalPlane]) -> Float? {
        planes.filter(\.isFloor).map(\.y).min()
    }
}
