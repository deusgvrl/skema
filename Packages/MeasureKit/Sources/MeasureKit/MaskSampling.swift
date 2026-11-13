import simd

extension DepthSampler {
    /// Like `worldPoints(in:box)` but keeps only depth pixels whose centre falls on a mask pixel that is 1
    /// after eroding the mask by `erosion` pixels (4-neighbourhood, applied `erosion` times; pixels outside
    /// the mask image count as 0). Erosion drops edge pixels where depth blends with the background.
    /// Then the same confidence filter and nearest-surface `depthBand` filter as the box version.
    public static func worldPoints(
        in mask: InstanceMask, depth: DepthFrame, camera: CameraModel,
        erosion: Int = 1, minConfidence: UInt8 = 2, depthBand: Float = 0.15, maxRange: Float = .infinity
    ) -> [SIMD3<Float>] {
        guard depth.width > 0, depth.height > 0, mask.width > 0, mask.height > 0,
              mask.pixels.count == mask.width * mask.height,
              depth.depth.count == depth.width * depth.height,
              depth.confidence.count == depth.depth.count else { return [] }

        let kept = eroded(mask, by: erosion)
        var candidates: [(i: Int, j: Int, d: Float)] = []
        for j in 0..<depth.height {
            let mj = min(mask.height - 1, Int((Float(j) + 0.5) / Float(depth.height) * Float(mask.height)))
            for i in 0..<depth.width {
                let mi = min(mask.width - 1, Int((Float(i) + 0.5) / Float(depth.width) * Float(mask.width)))
                guard kept[mj * mask.width + mi] != 0 else { continue }
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

    /// Every `stride`-th depth pixel (confidence >= minConfidence, finite positive depth) as a world point,
    /// with its normalized native-image position (pixel centre) for colour lookup.
    public static func scanPoints(
        depth: DepthFrame, camera: CameraModel, stride: Int = 2, minConfidence: UInt8 = 2
    ) -> [(world: SIMD3<Float>, uv: SIMD2<Float>, depth: Float)] {
        guard stride > 0, depth.width > 0, depth.height > 0,
              depth.depth.count == depth.width * depth.height,
              depth.confidence.count == depth.depth.count else { return [] }
        let scaleU = camera.imageResolution.x / Float(depth.width)
        let scaleV = camera.imageResolution.y / Float(depth.height)
        var points: [(world: SIMD3<Float>, uv: SIMD2<Float>, depth: Float)] = []
        for j in Swift.stride(from: 0, to: depth.height, by: stride) {
            for i in Swift.stride(from: 0, to: depth.width, by: stride) {
                let idx = j * depth.width + i
                let d = depth.depth[idx]
                guard depth.confidence[idx] >= minConfidence, d.isFinite, d > 0 else { continue }
                let pixel = SIMD2<Float>((Float(i) + 0.5) * scaleU, (Float(j) + 0.5) * scaleV)
                points.append((unproject(pixel: pixel, depth: d, camera: camera),
                               SIMD2((Float(i) + 0.5) / Float(depth.width), (Float(j) + 0.5) / Float(depth.height)),
                               d))
            }
        }
        return points
    }

    /// World points drawn as a mask in the camera's picture: a `width` x `height` grid over the whole native
    /// picture, with a 3 x 3 block marked around each point that is in view (cut at the edges).
    /// Used to keep an object's mask on screen as the phone moves. Nil when no point is in view.
    public static func projectedMask(
        of points: [SIMD3<Float>], camera: CameraModel, width: Int = 256, height: Int = 192
    ) -> InstanceMask? {
        guard width > 0, height > 0, camera.imageResolution.x > 0, camera.imageResolution.y > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        var any = false
        for point in points {
            guard let pixel = project(point, camera: camera) else { continue }
            let column = min(width - 1, Int(pixel.x / camera.imageResolution.x * Float(width)))
            let row = min(height - 1, Int(pixel.y / camera.imageResolution.y * Float(height)))
            for blockRow in max(0, row - 1)...min(height - 1, row + 1) {
                for blockColumn in max(0, column - 1)...min(width - 1, column + 1) {
                    pixels[blockRow * width + blockColumn] = 1
                }
            }
            any = true
        }
        return any ? InstanceMask(width: width, height: height, pixels: pixels) : nil
    }

    /// The world points of the depth pixels inside vertical columns: within `radius` metres of one of the axes through
    /// `anchors` (measured across the floor, x and z only) and with a height inside `heights`. One tap on an upright
    /// item collects it from its foot to its top. Only pixels with at least `minConfidence` and a usable depth count.
    public static func columnPoints(
        around anchors: [SIMD3<Float>], radius: Float, betweenY heights: ClosedRange<Float>,
        depth: DepthFrame, camera: CameraModel, minConfidence: UInt8 = 2
    ) -> [SIMD3<Float>] {
        guard depth.width > 0, depth.height > 0, depth.depth.count == depth.width * depth.height,
              depth.confidence.count == depth.depth.count else { return [] }
        let scaleU = camera.imageResolution.x / Float(depth.width)
        let scaleV = camera.imageResolution.y / Float(depth.height)
        var points: [SIMD3<Float>] = []
        for row in 0..<depth.height {
            for column in 0..<depth.width {
                let index = row * depth.width + column
                let pixelDepth = depth.depth[index]
                // Depth that is zero, negative or not a number says nothing about where the surface is.
                guard depth.confidence[index] >= minConfidence, pixelDepth.isFinite, pixelDepth > 0 else { continue }
                let pixel = SIMD2<Float>((Float(column) + 0.5) * scaleU, (Float(row) + 0.5) * scaleV)
                let world = unproject(pixel: pixel, depth: pixelDepth, camera: camera)
                guard heights.contains(world.y) else { continue }
                let onTheFloor = SIMD2(world.x, world.z)
                if anchors.contains(where: { simd_distance(SIMD2($0.x, $0.z), onTheFloor) <= radius }) {
                    points.append(world)
                }
            }
        }
        return points
    }

    /// The world point of the usable depth pixel nearest to a tap (fractions of the native picture, top-left),
    /// looking at most `searchRadius` depth pixels away. A usable pixel has a finite positive depth and at least
    /// `minConfidence`. At the same distance the higher confidence wins. Nil when there is none.
    public static func nearestPoint(
        toNormalized tap: SIMD2<Float>, depth: DepthFrame, camera: CameraModel,
        searchRadius: Int = 5, minConfidence: UInt8 = 1
    ) -> SIMD3<Float>? {
        guard depth.width > 0, depth.height > 0, depth.depth.count == depth.width * depth.height,
              depth.confidence.count == depth.depth.count else { return nil }
        let tapColumn = min(depth.width - 1, max(0, Int(tap.x * Float(depth.width))))
        let tapRow = min(depth.height - 1, max(0, Int(tap.y * Float(depth.height))))
        var best: (column: Int, row: Int, away: Float, confidence: UInt8)?
        for rowOffset in -searchRadius...searchRadius {
            for columnOffset in -searchRadius...searchRadius {
                let column = tapColumn + columnOffset, row = tapRow + rowOffset
                guard column >= 0, column < depth.width, row >= 0, row < depth.height else { continue }
                let index = row * depth.width + column
                let pixelDepth = depth.depth[index], confidence = depth.confidence[index]
                guard confidence >= minConfidence, pixelDepth.isFinite, pixelDepth > 0 else { continue }
                let away = (Float(columnOffset * columnOffset + rowOffset * rowOffset)).squareRoot()
                if let current = best, away > current.away || (away == current.away && confidence <= current.confidence) {
                    continue
                }
                best = (column, row, away, confidence)
            }
        }
        guard let best else { return nil }
        let pixel = SIMD2<Float>((Float(best.column) + 0.5) * camera.imageResolution.x / Float(depth.width),
                                 (Float(best.row) + 0.5) * camera.imageResolution.y / Float(depth.height))
        return unproject(pixel: pixel, depth: depth.depth[best.row * depth.width + best.column], camera: camera)
    }

    private static func eroded(_ mask: InstanceMask, by steps: Int) -> [UInt8] {
        var cur = mask.pixels
        let w = mask.width, h = mask.height
        for _ in 0..<max(0, steps) {
            var next = [UInt8](repeating: 0, count: cur.count)
            for j in 0..<h {
                for i in 0..<w where cur[j * w + i] != 0 {
                    guard i > 0, j > 0, i < w - 1, j < h - 1,
                          cur[j * w + i - 1] != 0, cur[j * w + i + 1] != 0,
                          cur[(j - 1) * w + i] != 0, cur[(j + 1) * w + i] != 0 else { continue }
                    next[j * w + i] = 1
                }
            }
            cur = next
        }
        return cur
    }
}
