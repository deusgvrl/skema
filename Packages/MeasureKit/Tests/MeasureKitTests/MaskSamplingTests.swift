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
