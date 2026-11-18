import simd

/// One time an object was seen: one detection on one frame.
public struct Sighting: Equatable, Sendable {
    public let label: String
    public let confidence: Float
    public let position: SIMD3<Float>   // Geometry.medianPoint of the object's world points
    public let axis: SIMD3<Float>?      // Geometry.principalAxis of the same points
    public let pointCount: Int
    /// The small box around the object's world points (A10-90 rule E, Cases D24–D26).
    public let box: WorldBox
    /// From a weak detection (35–49%): it may only join an ACCEPTED item and never starts one (Cases D21, D22, D36).
    public let isWeak: Bool

    public init(label: String, confidence: Float, position: SIMD3<Float>, axis: SIMD3<Float>?, pointCount: Int,
                box: WorldBox, isWeak: Bool = false) {
        self.box = box
        self.isWeak = isWeak
        self.label = label
        self.confidence = confidence
        self.position = position
        self.axis = axis
        self.pointCount = pointCount
    }

    /// Samples the detection's mask when it has one, else its box; nil when fewer than `minPoints` points.
    /// Depth pixels farther than `maxRange` metres are ignored (default: no limit).
    public static func make(from detection: Detection, depth: DepthFrame, camera: CameraModel,
                            minPoints: Int = 20, maxRange: Float = .infinity,
                            isWeak: Bool = false) -> Sighting? {
        let points = detection.mask.map { DepthSampler.worldPoints(in: $0, depth: depth, camera: camera, maxRange: maxRange) }
            ?? DepthSampler.worldPoints(in: detection.box, depth: depth, camera: camera, maxRange: maxRange)
        guard points.count >= minPoints, let position = Geometry.medianPoint(points),
              let box = WorldBox.around(points) else { return nil }
        return Sighting(label: detection.label, confidence: detection.confidence, position: position,
                        axis: Geometry.principalAxis(points), pointCount: points.count,
                        box: box, isWeak: isWeak)
    }
}
