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

    /// A mask the size of the depth frame: 1 for each depth pixel whose world point is within `radius` metres of one of
    /// the vertical axes through the `anchors` (measured across the floor, x and z only) and whose height is inside
    /// `heights`, 0 for every other pixel. One tap on an upright item marks it from its foot to its top.
    public static func mask(
        inColumnsAround anchors: [SIMD3<Float>], radius: Float, betweenY heights: ClosedRange<Float>,
        depth: DepthFrame, camera: CameraModel
    ) -> InstanceMask {
        var pixels = [UInt8](repeating: 0, count: depth.width * depth.height)
        guard !pixels.isEmpty, depth.depth.count == pixels.count else {
            return InstanceMask(width: depth.width, height: depth.height, pixels: pixels)
        }
        let scaleU = camera.imageResolution.x / Float(depth.width)
        let scaleV = camera.imageResolution.y / Float(depth.height)
        for row in 0..<depth.height {
            for column in 0..<depth.width {
                let pixelDepth = depth.depth[row * depth.width + column]
                // Depth that is zero, negative or not a number says nothing about where the surface is.
                guard pixelDepth.isFinite, pixelDepth > 0 else { continue }
                let imagePixel = SIMD2<Float>((Float(column) + 0.5) * scaleU, (Float(row) + 0.5) * scaleV)
                let world = unproject(pixel: imagePixel, depth: pixelDepth, camera: camera)
                guard heights.contains(world.y) else { continue }
                // Across the floor only: x and z count, so it does not matter how high the tap was.
                let onTheFloor = SIMD2(world.x, world.z)
                if anchors.contains(where: { simd_distance(SIMD2($0.x, $0.z), onTheFloor) <= radius }) {
                    pixels[row * depth.width + column] = 1
                }
            }
        }
        return InstanceMask(width: depth.width, height: depth.height, pixels: pixels)
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

extension InstanceMask {
    /// The marked pixels as a small number of boxes to draw. It looks at every `step`-th pixel of every `step`-th row
    /// and makes one box for each run of marked pixels in a row. Boxes are normalised to the mask (0 to 1, top-left
    /// origin), and each covers `step` pixels in height and `step` pixels for each sampled pixel in width.
    public func runBoxes(everyPixels step: Int) -> [NormalizedBox] {
        guard step > 0, width > 0, height > 0, pixels.count == width * height else { return [] }
        var boxes: [NormalizedBox] = []
        for row in stride(from: 0, to: height, by: step) {
            // The first and last sampled column of the run of marked pixels being followed in this row.
            var run: (first: Int, last: Int)?
            for column in stride(from: 0, to: width, by: step) {
                if pixels[row * width + column] != 0 {
                    run = (run?.first ?? column, column)
                } else if let finished = run {
                    boxes.append(box(of: finished, row: row, step: step))
                    run = nil
                }
            }
            if let finished = run { boxes.append(box(of: finished, row: row, step: step)) }
        }
        return boxes
    }

    /// The box for a run: from its first sampled column to the end of its last, and `step` rows high (cut at the edge).
    private func box(of run: (first: Int, last: Int), row: Int, step: Int) -> NormalizedBox {
        let right = min(run.last + step, width)
        let bottom = min(row + step, height)
        return NormalizedBox(
            x: Double(run.first) / Double(width), y: Double(row) / Double(height),
            width: Double(right - run.first) / Double(width), height: Double(bottom - row) / Double(height)
        )
    }
}

extension InstanceMask {
    /// How much of the smaller mask lies on the other one: the marked pixels both share, divided by the marked pixels
    /// of the mask with fewer. 1 means one lies inside the other, 0 means they do not touch. Two detections that share
    /// most of the smaller one are the same object. 0 when either mask has no marked pixel or the sizes differ.
    public func overlapShare(with other: InstanceMask) -> Double {
        guard width == other.width, height == other.height, pixels.count == other.pixels.count else { return 0 }
        var shared = 0, ownCount = 0, otherCount = 0
        for index in pixels.indices {
            let own = pixels[index] != 0, theirs = other.pixels[index] != 0
            if own { ownCount += 1 }
            if theirs { otherCount += 1 }
            if own && theirs { shared += 1 }
        }
        let smaller = min(ownCount, otherCount)
        return smaller == 0 ? 0 : Double(shared) / Double(smaller)
    }
}
