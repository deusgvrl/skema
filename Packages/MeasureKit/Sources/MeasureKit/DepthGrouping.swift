import simd

/// The paint bucket (A10-90): neighbouring depth pixels belong to one surface while their depths change only a little;
/// a bigger step is an edge. A10-106 starts the paint at the photographer's tap to find the whole tapped item.
public enum DepthGrouping {
    /// A depth step of this much or more between neighbours is an edge (Amadeus, 16 Nov: 5 cm).
    public static let maxStep: Float = 0.05
    /// Only depth pixels LiDAR is sure about start or spread the paint.
    public static let minConfidence: UInt8 = 2
    /// The paint never reaches a point lower than this above the floor (Amadeus, 20 Nov: 3 cm, the column's gap),
    /// so a light standing on the floor does not take the floor with it.
    public static let floorGap: Float = 0.03
    /// How far (depth pixels, up, down and sideways) from the tap the paint looks for a sure pixel to start on.
    public static let searchRadius = 5

    /// Case D12: do two neighbouring depths (metres) belong to the same surface?
    public static func isSameSurface(_ first: Float, _ second: Float) -> Bool {
        abs(first - second) < maxStep
    }

    /// A10-106 cases 1–5: the world points of the surface under a tap (`tap` in fractions of the picture, top-left).
    /// The paint starts on the nearest sure pixel within `searchRadius` (the nearer wins; same distance, the first
    /// row then column), then spreads to the 4 touching pixels that are sure, `isSameSurface` and at least
    /// `floorGap` above `floorY`. No reach limit (Amadeus, 20 Nov). Empty when no sure pixel is near the tap.
    public static func surface(fromNormalized tap: SIMD2<Float>, depth: DepthFrame, camera: CameraModel,
                               floorY: Float) -> [SIMD3<Float>] {
        let count = depth.width * depth.height
        guard depth.width > 0, depth.height > 0, depth.depth.count == count, depth.confidence.count == count
        else { return [] }
        let scale = SIMD2(camera.imageResolution.x / Float(depth.width), camera.imageResolution.y / Float(depth.height))
        func world(_ index: Int) -> SIMD3<Float> {
            let pixel = SIMD2(Float(index % depth.width) + 0.5, Float(index / depth.width) + 0.5) * scale
            return DepthSampler.unproject(pixel: pixel, depth: depth.depth[index], camera: camera)
        }
        var points: [Int: SIMD3<Float>] = [:]
        func usable(_ index: Int) -> Bool {
            let value = depth.depth[index]
            guard depth.confidence[index] >= minConfidence, value.isFinite, value > 0 else { return false }
            let point = world(index)
            guard point.y >= floorY + floorGap else { return false }
            points[index] = point
            return true
        }
        guard let seed = nearestUsable(to: tap, depth: depth, usable: usable) else { return [] }

        var painted: Set<Int> = [seed]
        var stack = [seed]
        while let current = stack.popLast() {
            for next in neighbours(of: current, width: depth.width, height: depth.height)
            where !painted.contains(next) && isSameSurface(depth.depth[current], depth.depth[next]) && usable(next) {
                painted.insert(next)
                stack.append(next)
            }
        }
        return painted.sorted().compactMap { points[$0] }
    }

    /// The usable depth pixel nearest to the tap, at most `searchRadius` pixels away on each axis.
    private static func nearestUsable(to tap: SIMD2<Float>, depth: DepthFrame, usable: (Int) -> Bool) -> Int? {
        let tapColumn = Swift.min(depth.width - 1, Swift.max(0, Int(tap.x * Float(depth.width))))
        let tapRow = Swift.min(depth.height - 1, Swift.max(0, Int(tap.y * Float(depth.height))))
        var best: (index: Int, away: Int)?
        for rowOffset in -searchRadius...searchRadius {
            for columnOffset in -searchRadius...searchRadius {
                let column = tapColumn + columnOffset, row = tapRow + rowOffset
                let away = columnOffset * columnOffset + rowOffset * rowOffset
                guard column >= 0, column < depth.width, row >= 0, row < depth.height,
                      away < (best?.away ?? Int.max), usable(row * depth.width + column) else { continue }
                best = (row * depth.width + column, away)
            }
        }
        return best?.index
    }

    /// The up, down, left and right neighbours of a depth pixel that are inside the grid.
    private static func neighbours(of index: Int, width: Int, height: Int) -> [Int] {
        let column = index % width, row = index / width
        var result: [Int] = []
        if column > 0 { result.append(index - 1) }
        if column < width - 1 { result.append(index + 1) }
        if row > 0 { result.append(index - width) }
        if row < height - 1 { result.append(index + width) }
        return result
    }
}
