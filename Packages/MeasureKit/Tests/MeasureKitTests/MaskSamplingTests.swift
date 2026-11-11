import Testing
import simd
@testable import MeasureKit

@Suite struct MaskSamplingTests {
    /// 20x10 depth: object rectangle (cols 5...14, rows 2...7) at 1 m, rest at `other` metres.
    private func scene(other: Float) -> (DepthFrame, InstanceMask) {
        var depth = [Float](repeating: other, count: 200)
        var mask = [UInt8](repeating: 0, count: 200)
        for j in 2...7 { for i in 5...14 { depth[j * 20 + i] = 1; mask[j * 20 + i] = 1 } }
        return (DepthFrame(width: 20, height: 10, depth: depth, confidence: [UInt8](repeating: 2, count: 200)),
                InstanceMask(width: 20, height: 10, pixels: mask))
    }

    @Test func onlyMaskedPixelsAndEdgeDroppedByErosion() {
        // Background at 1.05 m is inside the depth band, so only the mask can drop it.
        let (f, m) = scene(other: 1.05)
        let raw = DepthSampler.worldPoints(in: m, depth: f, camera: makeCamera(), erosion: 0)
        let eroded = DepthSampler.worldPoints(in: m, depth: f, camera: makeCamera(), erosion: 1)
        #expect(raw.count == 60)       // 10 x 6 mask pixels
        #expect(eroded.count == 32)    // 4-neighbourhood erosion: 8 x 4
        #expect(raw.allSatisfy { near($0.z, -1) })
        #expect(eroded.allSatisfy { near($0.z, -1) })
    }

    @Test func tableBesideTheMaskContributesNothing() {
        // Table strip directly under the object (rows 8...9) at 0.95 m, inside the depth band.
        var (f, m) = scene(other: 3)
        var depth = f.depth
        for j in 8...9 { for i in 5...14 { depth[j * 20 + i] = 0.95 } }
        f = DepthFrame(width: 20, height: 10, depth: depth, confidence: f.confidence)
        m = InstanceMask(width: 20, height: 10, pixels: m.pixels)
        let pts = DepthSampler.worldPoints(in: m, depth: f, camera: makeCamera(), erosion: 0)
        #expect(pts.count == 60)
        #expect(pts.allSatisfy { near($0.z, -1) })
    }

    @Test func lowerResolutionMaskIsSampledByNormalizedPosition() {
        // 10x5 mask, cols 2...4 and rows 1...3 set: depth pixel (i, j) reads mask (i / 2, j / 2).
        var px = [UInt8](repeating: 0, count: 50)
        for j in 1...3 { for i in 2...4 { px[j * 10 + i] = 1 } }
        let m = InstanceMask(width: 10, height: 5, pixels: px)
        let pts = DepthSampler.worldPoints(in: m, depth: makeFrame(depth: 1), camera: makeCamera(), erosion: 0)
        #expect(pts.count == 36)   // depth cols 4...9 x rows 2...7
    }

    /// The real bug: a standing bottle read 12 degrees tilt on the device.
    /// Scene: depth 80 x 160, camera with its principal point at the top edge (cy = 0, fx = fy = 100).
    /// A bottle 0.4 m tall and 0.1 m wide stands at 1 m depth (rows 64...127), on a horizontal table
    /// (y = -0.8 m, so depth * pixelY = 80) that runs toward the camera: rows 128...159, 1.0 m down to 0.8 m.
    /// The table pixels are in the depth band and have high confidence, so only the mask can remove them.
    @Test func tableDoesNotTiltAStandingBottle() throws {
        let k = simd_float3x3(columns: (SIMD3<Float>(100, 0, 0), SIMD3<Float>(0, 100, 0), SIMD3<Float>(100, 0, 1)))
        let camera = CameraModel(intrinsics: k, imageResolution: SIMD2(200, 100), cameraToWorld: matrix_identity_float4x4)
        let w = 80, h = 160
        var depth = [Float](repeating: 3, count: w * h)
        var mask = [UInt8](repeating: 0, count: w * h)
        for j in 64...127 { for i in 38...41 { depth[j * w + i] = 1; mask[j * w + i] = 1 } }
        for j in 128...159 {
            let pixelY = (Float(j) + 0.5) * 100 / Float(h)
            for i in 38...41 { depth[j * w + i] = 80 / pixelY }
        }
        let frame = DepthFrame(width: w, height: h, depth: depth, confidence: [UInt8](repeating: 2, count: w * h))
        let m = InstanceMask(width: w, height: h, pixels: mask)

        let boxPts = DepthSampler.worldPoints(in: NormalizedBox(x: 0.45, y: 0.45, width: 0.1, height: 0.55),
                                              depth: frame, camera: camera)
        let boxTilt = Geometry.tiltDegrees(axis: try #require(Geometry.principalAxis(boxPts)))
        let maskPts = DepthSampler.worldPoints(in: m, depth: frame, camera: camera)
        let maskTilt = Geometry.tiltDegrees(axis: try #require(Geometry.principalAxis(maskPts)))

        // Box version: table points tilt the axis (17.3 degrees here; the device read 12).
        // Mask version: only the bottle's own pixels, so it stands upright.
        #expect(boxTilt > Geometry.uprightToleranceDegrees)
        #expect(maskTilt < Geometry.uprightToleranceDegrees)
    }
}

/// A10-41 part 2: marking the depth pixels that belong to an item tapped in the debug screen. An item is a vertical
/// column around the tapped spot. A wall 2 m away, seen by `makeCamera()`, has its depth pixel centres at
/// x = 0.2 * column - 1.9 and y = 0.9 - 0.2 * row (metres), all at z = -2.
@Suite("Column region (A10-41)")
struct ColumnRegionTests {
    private let anyHeight: ClosedRange<Float> = -10...10

    private func marked(_ mask: InstanceMask, column: Int, row: Int) -> Bool {
        mask.pixels[row * mask.width + column] == 1
    }

    private func markedCount(_ mask: InstanceMask) -> Int {
        mask.pixels.filter { $0 == 1 }.count
    }

    @Test("A column covers the item from top to bottom")
    func columnCoversTheWholeHeight() {
        let frame = makeFrame(depth: 2)

        let mask = DepthSampler.mask(
            inColumnsAround: [SIMD3(0.1, 0, -2)], radius: 0.15, betweenY: anyHeight, depth: frame, camera: makeCamera()
        )

        for row in 0..<frame.height {
            #expect(marked(mask, column: 10, row: row))
        }
        #expect(markedCount(mask) == frame.height)
    }

    @Test("The height of the tap does not matter")
    func tapHeightDoesNotMatter() {
        let frame = makeFrame(depth: 2)

        let camera = makeCamera()
        let low = DepthSampler.mask(
            inColumnsAround: [SIMD3(0.1, -0.5, -2)], radius: 0.15, betweenY: anyHeight, depth: frame, camera: camera
        )
        let high = DepthSampler.mask(
            inColumnsAround: [SIMD3(0.1, 0.7, -2)], radius: 0.15, betweenY: anyHeight, depth: frame, camera: camera
        )

        #expect(markedCount(low) > 0)
        #expect(low == high)
    }

    @Test("Only the chosen heights are marked")
    func onlyTheChosenHeights() {
        let frame = makeFrame(depth: 2)

        let mask = DepthSampler.mask(
            inColumnsAround: [SIMD3(0.1, 0, -2)], radius: 0.15, betweenY: 0.0...0.45, depth: frame, camera: makeCamera()
        )

        // Rows 3 and 4 are at y = 0.3 and y = 0.1.
        #expect(marked(mask, column: 10, row: 3) && marked(mask, column: 10, row: 4))
        #expect(markedCount(mask) == 2)
    }

    @Test("The distance is measured across the floor: a wall behind the axis is not marked")
    func distanceIsAcrossTheFloor() {
        // The wall is 3 m away, 1 m behind the axis.
        let mask = DepthSampler.mask(
            inColumnsAround: [SIMD3(0.1, 0, -2)], radius: 0.3, betweenY: anyHeight,
            depth: makeFrame(depth: 3), camera: makeCamera()
        )

        #expect(mask.pixels.allSatisfy { $0 == 0 })
    }

    @Test("The axis is a place in the room: a moved camera marks the same world columns")
    func axisIsAWorldPlace() {
        var pose = matrix_identity_float4x4
        pose.columns.3 = SIMD4(0.5, 0, 1, 1)
        let axis = SIMD3<Float>(-0.25, 0, -2)
        let radius: Float = 0.4
        // The wall is at world z = -2, which is 3 m in front of a camera at z = 1.
        let frame = makeFrame(depth: 3)

        let mask = DepthSampler.mask(
            inColumnsAround: [axis], radius: radius, betweenY: anyHeight, depth: frame, camera: makeCamera(pose: pose)
        )

        // World x of each depth pixel, worked out by hand: x = 0.3 * column - 2.35.
        // The wall is at z = -2, like the axis, so only x decides.
        for row in 0..<frame.height {
            for column in 0..<frame.width {
                let inside = abs(0.3 * Float(column) - 2.35 - axis.x) <= radius
                #expect(marked(mask, column: column, row: row) == inside)
            }
        }
        #expect(markedCount(mask) == 3 * frame.height)
    }

    @Test("Two axes give two columns")
    func twoAxesTwoColumns() {
        let frame = makeFrame(depth: 2)
        // Each axis sits exactly on a pixel column: column 4 (x = -1.1) and column 15 (x = 1.1).
        let axes = [SIMD3<Float>(-1.1, 0, -2), SIMD3<Float>(1.1, 0, -2)]

        let mask = DepthSampler.mask(
            inColumnsAround: axes, radius: 0.05, betweenY: anyHeight, depth: frame, camera: makeCamera()
        )

        for row in 0..<frame.height {
            #expect(marked(mask, column: 4, row: row) && marked(mask, column: 15, row: row))
        }
        #expect(markedCount(mask) == 2 * frame.height)
    }

    @Test("Depth that is zero, negative or not a number is never marked")
    func unusableDepthNeverMarked() {
        // A zero depth lands on the camera itself, so an axis at the camera would catch it if it were not skipped.
        var depth = [Float](repeating: 2, count: 200)
        depth[4 * 20 + 9] = 0
        depth[4 * 20 + 10] = -0.05
        depth[5 * 20 + 9] = .nan
        let frame = DepthFrame(width: 20, height: 10, depth: depth, confidence: [UInt8](repeating: 2, count: 200))

        let mask = DepthSampler.mask(
            inColumnsAround: [SIMD3(0, 0, 0)], radius: 0.3, betweenY: -1...1, depth: frame, camera: makeCamera()
        )

        #expect(mask.pixels.allSatisfy { $0 == 0 })
    }
}

/// A10-41 part 2: the detector's mask as a few boxes to draw on the screen.
@Suite("Mask run boxes (A10-41)")
struct RunBoxesTests {
    /// A mask of `size` by `size` pixels with the given (column, row) pixels marked.
    private func mask(size: Int = 8, marked: [(column: Int, row: Int)]) -> InstanceMask {
        var pixels = [UInt8](repeating: 0, count: size * size)
        for pixel in marked { pixels[pixel.row * size + pixel.column] = 1 }
        return InstanceMask(width: size, height: size, pixels: pixels)
    }

    @Test("A filled block gives one box for the sampled row it covers")
    func filledBlock() {
        // Columns 2 to 5 and rows 2 and 3 are marked.
        let block = (2...5).flatMap { column in (2...3).map { row in (column: column, row: row) } }

        let boxes = mask(marked: block).runBoxes(everyPixels: 2)

        #expect(boxes == [NormalizedBox(x: 0.25, y: 0.25, width: 0.5, height: 0.25)])
    }

    @Test("A gap splits a row into two runs")
    func gapSplitsARow() {
        let row = [0, 1, 4, 5].map { (column: $0, row: 0) }

        let boxes = mask(marked: row).runBoxes(everyPixels: 2)

        #expect(boxes == [
            NormalizedBox(x: 0, y: 0, width: 0.25, height: 0.25),
            NormalizedBox(x: 0.5, y: 0, width: 0.25, height: 0.25)
        ])
    }

    @Test("The step skips pixels: a full mask gives one wide box per sampled row")
    func stepSkipsPixels() {
        let all = (0..<8).flatMap { column in (0..<8).map { row in (column: column, row: row) } }

        let boxes = mask(marked: all).runBoxes(everyPixels: 4)

        #expect(boxes == [
            NormalizedBox(x: 0, y: 0, width: 1, height: 0.5),
            NormalizedBox(x: 0, y: 0.5, width: 1, height: 0.5)
        ])
    }

    @Test("A box at the edge is cut to the mask when the size is not a multiple of the step")
    func boxIsCutAtTheEdge() {
        // 5 by 5 fully marked, every 4 pixels: the second sampled row and column only have 1 pixel left.
        let all = (0..<5).flatMap { column in (0..<5).map { row in (column: column, row: row) } }

        let boxes = mask(size: 5, marked: all).runBoxes(everyPixels: 4)

        #expect(boxes == [
            NormalizedBox(x: 0, y: 0, width: 1, height: 0.8),
            NormalizedBox(x: 0, y: 0.8, width: 1, height: 0.2)
        ])
    }

    @Test("An empty mask, an empty size or a bad step gives no boxes")
    func nothingToDraw() {
        #expect(mask(marked: []).runBoxes(everyPixels: 2).isEmpty)
        #expect(InstanceMask(width: 0, height: 0, pixels: []).runBoxes(everyPixels: 2).isEmpty)
        #expect(mask(marked: [(column: 1, row: 1)]).runBoxes(everyPixels: 0).isEmpty)
    }
}

/// How much of one mask lies on another, to tell whether two detections are the same object.
@Suite("Mask overlap (A10-41)")
struct MaskOverlapTests {
    /// A mask of `size` by `size` pixels with the given (column, row) pixels marked.
    private func mask(size: Int = 8, marked: [(column: Int, row: Int)]) -> InstanceMask {
        var pixels = [UInt8](repeating: 0, count: size * size)
        for pixel in marked { pixels[pixel.row * size + pixel.column] = 1 }
        return InstanceMask(width: size, height: size, pixels: pixels)
    }

    private func block(columns: ClosedRange<Int>, rows: ClosedRange<Int>) -> [(column: Int, row: Int)] {
        columns.flatMap { column in rows.map { row in (column: column, row: row) } }
    }

    @Test("Identical masks share everything")
    func identical() {
        let one = mask(marked: block(columns: 2...3, rows: 2...3))

        #expect(one.overlapShare(with: one) == 1)
    }

    @Test("Masks that do not touch share nothing")
    func apart() {
        let left = mask(marked: block(columns: 0...1, rows: 0...1))
        let right = mask(marked: block(columns: 5...6, rows: 5...6))

        #expect(left.overlapShare(with: right) == 0)
    }

    @Test("A small mask inside a big one counts as the same object, whichever way round")
    func inside() {
        let small = mask(marked: block(columns: 1...2, rows: 1...2))
        let big = mask(marked: block(columns: 0...3, rows: 0...3))

        #expect(small.overlapShare(with: big) == 1)
        #expect(big.overlapShare(with: small) == 1)
    }

    @Test("A partial overlap is a fraction of the smaller mask")
    func partial() {
        let first = mask(marked: block(columns: 0...1, rows: 0...1))
        let second = mask(marked: block(columns: 1...2, rows: 0...1))

        #expect(first.overlapShare(with: second) == 0.5)
    }

    @Test("Empty masks and masks of different sizes share nothing, without crashing")
    func nothingToCompare() {
        let marked = mask(marked: block(columns: 0...1, rows: 0...1))
        let empty = mask(marked: [])
        let otherSize = mask(size: 4, marked: block(columns: 0...1, rows: 0...1))
        let zeroSize = InstanceMask(width: 0, height: 0, pixels: [])
        // The same number of pixels in a different shape is not comparable either.
        let wide = InstanceMask(width: 16, height: 4, pixels: [UInt8](repeating: 1, count: 64))
        let square = InstanceMask(width: 8, height: 8, pixels: [UInt8](repeating: 1, count: 64))

        #expect(wide.overlapShare(with: square) == 0)
        #expect(marked.overlapShare(with: empty) == 0)
        #expect(empty.overlapShare(with: empty) == 0)
        #expect(marked.overlapShare(with: otherSize) == 0)
        #expect(zeroSize.overlapShare(with: zeroSize) == 0)
    }
}
