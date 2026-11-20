import simd

extension DepthSampler {
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
}
