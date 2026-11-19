import simd

/// Turns depth pixels into world-space points.
public enum DepthSampler {
    /// Unprojects an image pixel at z-depth `depth` (metres) to world space.
    /// Computer-vision camera point `(x, y, z)`, flipped to ARKit camera space `(x, -y, -z)`, then `cameraToWorld`.
    public static func unproject(pixel: SIMD2<Float>, depth: Float, camera: CameraModel) -> SIMD3<Float> {
        let k = camera.intrinsics
        let fx = k[0][0], fy = k[1][1], cx = k[2][0], cy = k[2][1]
        let x = (pixel.x - cx) * depth / fx
        let y = (pixel.y - cy) * depth / fy
        let world = camera.cameraToWorld * SIMD4<Float>(x, -y, -depth, 1)
        return SIMD3<Float>(world.x, world.y, world.z)
    }

    /// Closer than this many metres in front of the camera, a spot gets no pixel (dividing by ~0 depth).
    public static let minProjectDepth: Float = 0.01

    /// The opposite of `unproject` (A10-62): a world-space spot to its pixel in the camera picture.
    /// Nil when the spot is behind the camera, closer than `minProjectDepth`, or outside the picture.
    public static func project(_ world: SIMD3<Float>, camera: CameraModel) -> SIMD2<Float>? {
        let local = camera.cameraToWorld.inverse * SIMD4<Float>(world, 1)
        let depth = -local.z                                   // ARKit camera space looks along -z
        guard depth >= minProjectDepth else { return nil }
        let k = camera.intrinsics
        let fx = k[0][0], fy = k[1][1], cx = k[2][0], cy = k[2][1]
        let pixel = SIMD2<Float>(fx * local.x / depth + cx, fy * -local.y / depth + cy)
        let size = camera.imageResolution
        guard pixel.x >= 0, pixel.x < size.x, pixel.y >= 0, pixel.y < size.y else { return nil }
        return pixel
    }

    /// Depth pixels farther than this many metres from the iPhone are ignored (temporary, finalised in A10-24).
    public static let maxRange: Float = 5.0
}
