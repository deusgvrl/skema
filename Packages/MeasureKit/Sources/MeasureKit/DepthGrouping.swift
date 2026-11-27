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

    // MARK: A tapped item, one frame (27 Nov)

    /// The column the off-screen check (`FieldOfView`) uses for the subject and the camera: this far around the
    /// tapped spot (across the floor), from `columnFloorGap` above the floor up to `columnHeight` above it.
    public static let columnRadius: Float = 0.10
    public static let columnFloorGap: Float = 0.03
    public static let columnHeight: Float = 3.0

    /// A frame is skipped for an item when the depth at its tapped spot is this far (metres) from the spot's own
    /// distance: something stands in front of it, or the phone looks past it.
    public static let startTolerance: Float = 0.15
    /// Two neighbouring dots are one surface while their depths differ by at most this much (metres), or by
    /// `farShare` of the distance when that is more, so a far surface is not cut by LiDAR's noise...
    public static let minEdgeStep: Float = 0.03
    public static let farShare: Float = 0.01
    /// ...or while they carry on the slope of the two dots before them (a surface seen at a steep angle), as long
    /// as the step is at most this much.
    public static let maxSlopeStep: Float = 0.25
    /// How far (metres) from the tapped spot an item can reach.
    public static func reach(_ kind: ItemKind) -> Float {
        kind == .camera ? 0.6 : 1.5
    }
    /// An item's dots stay this far above the flat surface it stands on (a tabletop, a desk).
    public static let supportGap: Float = 0.02
    /// A layer counts as what an item stands on when it is at least this wide and has this many dots.
    public static let supportMinWidth: Float = 0.25
    public static let supportMinPoints = 20
    /// ... and its dots lie on at least this many rows of the depth picture: a desktop seen from above covers many
    /// rows in one 1 cm layer, an upright surface (a softbox's front, a tripod leg, a person) only one or two.
    public static let supportMinRows = 6
    /// A wall or backdrop in the paint: an upright flat surface at least this long and this tall, that the tapped
    /// spot is more than `backgroundGap` away from. Its dots are dropped.
    public static let backgroundMinLength: Float = 1.0
    public static let backgroundMinHeight: Float = 0.8
    public static let backgroundGap: Float = 0.04
    private static let planeTolerance: Float = 0.02

    /// One frame's dots of a tapped item, or nil when the frame tells nothing about it: the tapped spot is out of the
    /// picture, or something else is in front of it (`startTolerance`). Empty when no sure dot is near the spot.
    ///
    /// The paint starts at the tapped spot and spreads to neighbours that are sure, at least `floorGap` above the
    /// floor, within `reach` of the spot and on the same surface (`minEdgeStep`, `farShare`, `maxSlopeStep`). Then it
    /// drops a wall or backdrop the spot is not on, and a flat surface the item stands on (a desk; a tripod or a stand
    /// has none); the dots still joined to the spot are the item's. A light or a camera keeps only its head: the wide part, not its stand.
    public static func itemPoints(_ kind: ItemKind, anchor: SIMD3<Float>, depth: DepthFrame, camera: CameraModel,
                                  floorY: Float) -> [SIMD3<Float>]? {
        let width = depth.width, height = depth.height, count = width * height
        guard width > 0, height > 0, depth.depth.count == count, depth.confidence.count == count,
              let pixel = DepthSampler.project(anchor, camera: camera) else { return nil }
        let anchorDepth = -(camera.cameraToWorld.inverse * SIMD4<Float>(anchor, 1)).z
        let scale = SIMD2(camera.imageResolution.x / Float(width), camera.imageResolution.y / Float(height))
        let reach = Self.reach(kind)
        var points: [Int: SIMD3<Float>] = [:]
        func usable(_ index: Int) -> Bool {
            if points[index] != nil { return true }
            let value = depth.depth[index]
            guard depth.confidence[index] >= minConfidence, value.isFinite, value > 0 else { return false }
            let world = DepthSampler.unproject(
                pixel: SIMD2(Float(index % width) + 0.5, Float(index / width) + 0.5) * scale, depth: value,
                camera: camera)
            guard world.y >= floorY + floorGap, simd_distance(world, anchor) <= reach else { return false }
            points[index] = world
            return true
        }
        // No sure dot near the spot paints nothing (the frame still counts, as before); a dot at another distance is
        // something else in front of the spot, so the frame tells nothing.
        guard let seed = nearestUsable(to: pixel / camera.imageResolution, depth: depth, usable: usable) else { return [] }
        guard abs(depth.depth[seed] - anchorDepth) <= startTolerance else { return nil }

        var painted = paint(from: seed, depth: depth, usable: usable)
        var kept = Set(painted)
        let dots = painted.compactMap { index in points[index].map { (index, $0) } }
        for (index, _) in backgroundDots(dots, anchor: anchor) { kept.remove(index) }
        if let support = supportTop(dots, below: anchor, width: width) {
            for (index, point) in dots where point.y < support + supportGap { kept.remove(index) }
        }
        painted = joined(to: seed, among: kept, width: width, height: height)
        let item = painted.compactMap { points[$0] }
        guard kind != .subject, let lowest = item.map(\.y).min() else { return item }
        return Geometry.headPoints(of: item, lowest: lowest)
    }

    /// The paint from `seed` over the pixels `usable` lets in, by the edge rules of `itemPoints`.
    private static func paint(from seed: Int, depth: DepthFrame, usable: (Int) -> Bool) -> [Int] {
        let width = depth.width
        var painted: Set<Int> = [seed]
        var order = [seed]
        var queue = [seed], head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            for next in neighbours(of: current, width: width, height: depth.height) where !painted.contains(next) {
                guard usable(next), joins(current, next, painted: painted, depth: depth) else { continue }
                painted.insert(next)
                order.append(next)
                queue.append(next)
            }
        }
        return order
    }

    /// Whether `next` is on the same surface as `current`: a small step for the distance, or the same slope as the
    /// step that led to `current` (the pixel on its other side, when painted).
    private static func joins(_ current: Int, _ next: Int, painted: Set<Int>, depth: DepthFrame) -> Bool {
        let here = depth.depth[current], there = depth.depth[next]
        let allowed = max(minEdgeStep, farShare * here)
        let step = abs(there - here)
        if step <= allowed { return true }
        guard step <= maxSlopeStep else { return false }
        let before = current - (next - current)
        let sameRow = abs(next - current) == 1 ? before / depth.width == current / depth.width : true
        guard before >= 0, before < depth.depth.count, sameRow, painted.contains(before) else { return false }
        return abs(there - (2 * here - depth.depth[before])) <= allowed
    }

    /// The pixels of `kept` that still touch `seed` through other kept pixels.
    private static func joined(to seed: Int, among kept: Set<Int>, width: Int, height: Int) -> [Int] {
        guard kept.contains(seed) else { return [] }
        var reached: Set<Int> = [seed]
        var stack = [seed]
        while let current = stack.popLast() {
            for next in neighbours(of: current, width: width, height: height)
            where kept.contains(next) && !reached.contains(next) {
                reached.insert(next)
                stack.append(next)
            }
        }
        return reached.sorted()
    }

    /// The top of the flat layer an item stands on: the highest 1 cm layer below the tapped spot (by at least
    /// `supportGap`) that is `supportMinWidth` wide on the floor, has `supportMinPoints` dots and lies down
    /// (`supportMinRows` rows of the depth picture, `width` pixels wide). Nil when none, as on a tripod or a stand.
    static func supportTop(_ dots: [(Int, SIMD3<Float>)], below anchor: SIMD3<Float>, width: Int) -> Float? {
        var layers: [Int: [(Int, SIMD3<Float>)]] = [:]
        for dot in dots where dot.1.y < anchor.y - supportGap {
            layers[Int((dot.1.y / 0.01).rounded(.down)), default: []].append(dot)
        }
        let flat = layers.filter { layer in
            guard layer.value.count >= supportMinPoints else { return false }
            let xs = layer.value.map(\.1.x), zs = layer.value.map(\.1.z)
            guard max(xs.max()! - xs.min()!, zs.max()! - zs.min()!) >= supportMinWidth else { return false }
            return Set(layer.value.map { $0.0 / width }).count >= supportMinRows
        }
        guard let top = flat.keys.max(), let members = flat[top] else { return nil }
        return members.map(\.1.y).max()
    }

    /// The dots of the biggest upright flat surface (a wall, a backdrop) in `dots`, when it is at least
    /// `backgroundMinLength` long and `backgroundMinHeight` tall and the tapped spot is not on it. Seen from above, such
    /// a surface is a straight line, found by trying lines through pairs of dots.
    static func backgroundDots(_ dots: [(Int, SIMD3<Float>)], anchor: SIMD3<Float>) -> [(Int, SIMD3<Float>)] {
        guard dots.count >= 50 else { return [] }
        let tries = 60
        var best: [(Int, SIMD3<Float>)] = []
        var bestLine: (point: SIMD2<Float>, normal: SIMD2<Float>)?
        for attempt in 0..<tries {
            let first = dots[(attempt * 7919) % dots.count].1, second = dots[(attempt * 104_729 + dots.count / 2) % dots.count].1
            let start = SIMD2(first.x, first.z), along = SIMD2(second.x, second.z) - start
            guard simd_length(along) > 0.2 else { continue }
            let normal = simd_normalize(SIMD2(-along.y, along.x))
            let inliers = dots.filter { abs(simd_dot(SIMD2($0.1.x, $0.1.z) - start, normal)) <= planeTolerance }
            if inliers.count > best.count {
                best = inliers
                bestLine = (start, normal)
            }
        }
        guard let line = bestLine,
              abs(simd_dot(SIMD2(anchor.x, anchor.z) - line.point, line.normal)) > backgroundGap else { return [] }
        let direction = SIMD2(line.normal.y, -line.normal.x)
        let positions = best.map { simd_dot(SIMD2($0.1.x, $0.1.z) - line.point, direction) }
        let heights = best.map(\.1.y)
        guard positions.max()! - positions.min()! >= backgroundMinLength,
              heights.max()! - heights.min()! >= backgroundMinHeight else { return [] }
        return best
    }
}

/// What a tap set; it decides how the item's dots are picked out and measured.
public enum ItemKind: Sendable {
    case subject, light, camera
}

