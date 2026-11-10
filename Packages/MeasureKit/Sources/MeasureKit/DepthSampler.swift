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

    /// Share of a box's depth pixels that counts as a real surface rather than stray pixels.
    public static let minSurfaceFraction: Float = 0.2

    /// Depth pixels farther than this many metres from the iPhone are ignored (temporary, finalised in A10-24).
    public static let maxRange: Float = 5.0

    /// Depth pixels inside `box` shrunk by `inset` (fraction of width/height) on each side,
    /// with confidence >= `minConfidence`, kept only within `depthBand` metres of the nearest surface,
    /// unprojected to world space. The nearest surface wins even when background fills most of the box,
    /// because a detected object sits in front of what is behind it.
    public static func worldPoints(
        in box: NormalizedBox, depth: DepthFrame, camera: CameraModel,
        minConfidence: UInt8 = 2, inset: Double = 0.1, depthBand: Float = 0.15, maxRange: Float = .infinity
    ) -> [SIMD3<Float>] {
        guard depth.width > 0, depth.height > 0, box.width > 0, box.height > 0,
              depth.depth.count == depth.width * depth.height,
              depth.confidence.count == depth.depth.count else { return [] }

        let x0 = box.x + box.width * inset, x1 = box.x + box.width * (1 - inset)
        let y0 = box.y + box.height * inset, y1 = box.y + box.height * (1 - inset)
        guard x1 > x0, y1 > y0 else { return [] }

        var candidates: [(i: Int, j: Int, d: Float)] = []
        for j in 0..<depth.height {
            let cy = (Double(j) + 0.5) / Double(depth.height)
            guard cy >= y0, cy <= y1 else { continue }
            for i in 0..<depth.width {
                let cx = (Double(i) + 0.5) / Double(depth.width)
                guard cx >= x0, cx <= x1 else { continue }
                let idx = j * depth.width + i
                let d = depth.depth[idx]
                guard depth.confidence[idx] >= minConfidence, d.isFinite, d > 0, d <= maxRange else { continue }
                candidates.append((i, j, d))
            }
        }
        guard !candidates.isEmpty else { return [] }

        let anchor = nearestSurfaceDepth(candidates.map(\.d).sorted(), depthBand: depthBand)
        let scaleU = camera.imageResolution.x / Float(depth.width)
        let scaleV = camera.imageResolution.y / Float(depth.height)
        return candidates.compactMap { c in
            guard abs(c.d - anchor) <= depthBand else { return nil }
            let pixel = SIMD2<Float>((Float(c.i) + 0.5) * scaleU, (Float(c.j) + 0.5) * scaleV)
            return unproject(pixel: pixel, depth: c.d, camera: camera)
        }
    }

    /// Median depth of the nearest `depthBand`-wide slice that holds at least `minSurfaceFraction`
    /// of `sorted` (ascending, non-empty). Falls back to the overall median when no slice qualifies.
    static func nearestSurfaceDepth(_ sorted: [Float], depthBand: Float) -> Float {
        let minCount = max(1, Int((minSurfaceFraction * Float(sorted.count)).rounded(.up)))
        var end = 0
        for start in sorted.indices {
            end = max(end, start)
            while end < sorted.count, sorted[end] - sorted[start] <= depthBand { end += 1 }
            if end - start >= minCount { return sorted[(start + end) / 2] }
        }
        return sorted[sorted.count / 2]
    }
}
