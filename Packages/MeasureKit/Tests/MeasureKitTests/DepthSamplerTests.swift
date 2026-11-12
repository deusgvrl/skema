import Testing
import simd
@testable import MeasureKit

@Suite struct DepthSamplerTests {
    @Test func principalPointMapsToMinusZ() {
        let p = DepthSampler.unproject(pixel: SIMD2(100, 50), depth: 2, camera: makeCamera())
        #expect(near(p, SIMD3(0, 0, -2)))
    }

    @Test func rightAndBelowMapsToPlusXMinusY() {
        let p = DepthSampler.unproject(pixel: SIMD2(150, 100), depth: 2, camera: makeCamera())
        #expect(near(p, SIMD3(1, -1, -2)))
    }

    @Test func honoursCameraToWorld() {
        var translated = matrix_identity_float4x4
        translated.columns.3 = SIMD4(1, 2, 3, 1)
        let a = DepthSampler.unproject(pixel: SIMD2(100, 50), depth: 2, camera: makeCamera(pose: translated))
        #expect(near(a, SIMD3(1, 2, 1)))

        // 90 degree yaw about +y: camera -z (forward) points to world -x.
        let yaw = simd_float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3(0, 1, 0)))
        let b = DepthSampler.unproject(pixel: SIMD2(100, 50), depth: 2, camera: makeCamera(pose: yaw))
        #expect(near(b, SIMD3(-2, 0, 0)))
    }

    @Test func flatWallGivesConstantZDepth() {
        let pts = DepthSampler.worldPoints(in: NormalizedBox(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
                                           depth: makeFrame(depth: 1.5), camera: makeCamera())
        #expect(!pts.isEmpty)
        #expect(pts.allSatisfy { near($0.z, -1.5) })
    }

    @Test func lowConfidenceDropped() {
        var f = makeFrame(depth: 1.5)
        var conf = f.confidence
        for i in 0..<conf.count where i % 2 == 0 { conf[i] = 1 }
        f = DepthFrame(width: f.width, height: f.height, depth: f.depth, confidence: conf)
        let box = NormalizedBox(x: 0, y: 0, width: 1, height: 1)
        let all = DepthSampler.worldPoints(in: box, depth: makeFrame(depth: 1.5), camera: makeCamera())
        let some = DepthSampler.worldPoints(in: box, depth: f, camera: makeCamera())
        #expect(some.count == all.count / 2)
        let none = DepthSampler.worldPoints(in: box, depth: makeFrame(depth: 1.5, confidence: 0), camera: makeCamera())
        #expect(none.isEmpty)
    }

    @Test func backgroundOutsideDepthBandDropped() {
        // Left 3/4 of the frame (columns 0..14) is the object at 1 m; the rest is background at 3 m.
        var depth = [Float](repeating: 3, count: 200)
        for j in 0..<10 { for i in 0..<15 { depth[j * 20 + i] = 1 } }
        let f = DepthFrame(width: 20, height: 10, depth: depth, confidence: [UInt8](repeating: 2, count: 200))
        let pts = DepthSampler.worldPoints(in: NormalizedBox(x: 0, y: 0, width: 1, height: 1),
                                           depth: f, camera: makeCamera(), inset: 0)
        #expect(!pts.isEmpty)
        #expect(pts.allSatisfy { near($0.z, -1) })
    }

    @Test func backgroundMajorityStillKeepsNearObject() {
        // Review finding 1: the object fills only 30% of the box (columns 0..5) at 1 m,
        // the wall behind fills 70% at 2.5 m. The object must win, not the wall.
        var depth = [Float](repeating: 2.5, count: 200)
        for j in 0..<10 { for i in 0..<6 { depth[j * 20 + i] = 1 } }
        let f = DepthFrame(width: 20, height: 10, depth: depth, confidence: [UInt8](repeating: 2, count: 200))
        let pts = DepthSampler.worldPoints(in: NormalizedBox(x: 0, y: 0, width: 1, height: 1),
                                           depth: f, camera: makeCamera(), inset: 0)
        #expect(pts.count == 60)
        #expect(pts.allSatisfy { near($0.z, -1) })
    }

    @Test func fewFlyingPixelsInFrontAreIgnored() {
        // Guard for the fix above: "nearest" must mean the nearest real surface,
        // not a handful of stray pixels (10 of 200) at 0.3 m.
        var depth = [Float](repeating: 1, count: 200)
        for i in 0..<10 { depth[i * 20] = 0.3 }
        let f = DepthFrame(width: 20, height: 10, depth: depth, confidence: [UInt8](repeating: 2, count: 200))
        let pts = DepthSampler.worldPoints(in: NormalizedBox(x: 0, y: 0, width: 1, height: 1),
                                           depth: f, camera: makeCamera(), inset: 0)
        #expect(pts.count == 190)
        #expect(pts.allSatisfy { near($0.z, -1) })
    }

    @Test func insetShrinksAndBadBoxGivesEmpty() {
        let box = NormalizedBox(x: 0, y: 0, width: 1, height: 1)
        let f = makeFrame(depth: 1)
        let full = DepthSampler.worldPoints(in: box, depth: f, camera: makeCamera(), inset: 0)
        let shrunk = DepthSampler.worldPoints(in: box, depth: f, camera: makeCamera(), inset: 0.25)
        #expect(full.count == 200)
        #expect(shrunk.count < full.count && !shrunk.isEmpty)
        #expect(DepthSampler.worldPoints(in: NormalizedBox(x: 0.5, y: 0.5, width: 0, height: 0),
                                         depth: f, camera: makeCamera()).isEmpty)
        #expect(DepthSampler.worldPoints(in: NormalizedBox(x: 2, y: 2, width: 0.5, height: 0.5),
                                         depth: f, camera: makeCamera()).isEmpty)
    }
}

/// A10-41 range cases. A flat wall at one depth puts every depth pixel at the same distance from the iPhone.
@Suite("Range filter (A10-41)")
struct RangeFilterTests {
    private let wholeImage = NormalizedBox(x: 0, y: 0, width: 1, height: 1)
    private let wholeMask = InstanceMask(width: 20, height: 10, pixels: [UInt8](repeating: 1, count: 200))

    private func boxPoints(wallAt depth: Float) -> [SIMD3<Float>] {
        DepthSampler.worldPoints(in: wholeImage, depth: makeFrame(depth: depth), camera: makeCamera(),
                                 inset: 0, maxRange: DepthSampler.maxRange)
    }

    private func maskPoints(wallAt depth: Float) -> [SIMD3<Float>] {
        DepthSampler.worldPoints(in: wholeMask, depth: makeFrame(depth: depth), camera: makeCamera(),
                                 erosion: 0, maxRange: DepthSampler.maxRange)
    }

    @Test("A surface 4 m away is kept")
    func nearSurfaceKept() {
        #expect(boxPoints(wallAt: 4).count == 200)
    }

    @Test("A surface 6 m away is dropped")
    func farSurfaceDropped() {
        #expect(boxPoints(wallAt: 6).isEmpty)
    }

    @Test("A surface exactly 5 m away is kept")
    func surfaceAtTheLimitKept() {
        #expect(boxPoints(wallAt: 5).count == 200)
    }

    @Test("The mask version keeps points up to exactly 5 m and drops the ones beyond")
    func maskVersionAlsoFilters() {
        #expect(maskPoints(wallAt: 4).count == 200)
        #expect(maskPoints(wallAt: 5).count == 200)
        #expect(maskPoints(wallAt: 6).isEmpty)
    }
}

/// A10-62 follow-up: a tap on the picture becomes a small box of depth pixels for the subject.
@Suite("Box around a tap")
struct BoxAroundTapTests {
    @Test("A tap in the middle gives a box of 2 x halfSize centred on it")
    func middle() {
        let box = NormalizedBox.around(x: 0.5, y: 0.25, halfSize: 0.04)
        #expect(abs(box.x - 0.46) < 1e-9 && abs(box.y - 0.21) < 1e-9)
        #expect(abs(box.width - 0.08) < 1e-9 && abs(box.height - 0.08) < 1e-9)
    }

    @Test("A tap near a corner is cut at the edges of the picture")
    func corner() {
        let box = NormalizedBox.around(x: 0.01, y: 0.99, halfSize: 0.04)
        #expect(box.x == 0 && abs(box.width - 0.05) < 1e-9)
        #expect(abs(box.y - 0.95) < 1e-9 && abs(box.height - 0.05) < 1e-9)
    }
}

/// A10-62 follow-up: points in the world drawn as a mask in the camera's picture.
@Suite("Projected mask")
struct ProjectedMaskTests {
    /// 256 x 192 grid over a 200 x 100 picture: the principal point (100, 50) is cell (128, 96).
    private func cells(_ mask: InstanceMask) -> [Int] {
        mask.pixels.indices.filter { mask.pixels[$0] != 0 }
    }

    @Test("A point straight ahead marks a 3 x 3 block around the middle cell")
    func pointAhead() throws {
        let mask = try #require(DepthSampler.projectedMask(of: [SIMD3(0, 0, -2)], camera: makeCamera()))

        #expect(mask.width == 256 && mask.height == 192)
        var expected: [Int] = []
        for row in 95...97 { for column in 127...129 { expected.append(row * 256 + column) } }
        #expect(cells(mask) == expected)
    }

    @Test("A point to the right of the camera lands to the right in the picture")
    func pointToTheRight() throws {
        let mask = try #require(DepthSampler.projectedMask(of: [SIMD3(0.5, 0, -2)], camera: makeCamera()))

        // 0.5 m at 2 m with fx = 100 is 25 px right of the centre: pixel 125 of 200, cell 160.
        #expect(cells(mask).contains(96 * 256 + 160))
    }

    @Test("Points behind the camera or outside the picture give no mask")
    func nothingInView() {
        #expect(DepthSampler.projectedMask(of: [SIMD3(0, 0, 2)], camera: makeCamera()) == nil)
        #expect(DepthSampler.projectedMask(of: [SIMD3(10, 0, -2)], camera: makeCamera()) == nil)
        #expect(DepthSampler.projectedMask(of: [], camera: makeCamera()) == nil)
    }

    @Test("A point at the edge is cut, not wrapped to the other side")
    func edgeIsCut() throws {
        // Pixel (199.5, 50) is the last column: its block must not reach column 0.
        let mask = try #require(DepthSampler.projectedMask(of: [SIMD3(0.995, 0, -1)], camera: makeCamera()))

        #expect(cells(mask).allSatisfy { $0 % 256 > 200 })
    }

    @Test("Two separate points give two blocks")
    func twoPoints() throws {
        let mask = try #require(DepthSampler.projectedMask(
            of: [SIMD3(-0.5, 0, -2), SIMD3(0.5, 0, -2)], camera: makeCamera()))

        #expect(cells(mask).count == 18)
    }
}

/// A10-41 painted items, kept as points: the depth pixels in a vertical column around a tapped spot.
/// A wall 2 m away has depth pixel centres at x = 0.2 x column - 1.9 and y = 0.9 - 0.2 x row (metres), all at z = -2.
@Suite("Column points")
struct ColumnPointsTests {
    private let anywhere: ClosedRange<Float> = -10...10

    @Test("A column covers the item from top to bottom")
    func columnCoversTheItem() {
        let points = DepthSampler.columnPoints(around: [SIMD3(0.1, 0, -2)], radius: 0.15, betweenY: anywhere,
                                               depth: makeFrame(depth: 2), camera: makeCamera())

        #expect(points.count == 10)
        #expect(points.allSatisfy { near($0.x, 0.1) && near($0.z, -2) })
    }

    @Test("The height of the tap does not matter")
    func tapHeightDoesNotMatter() {
        let low = DepthSampler.columnPoints(around: [SIMD3(0.1, -0.7, -2)], radius: 0.15, betweenY: anywhere,
                                            depth: makeFrame(depth: 2), camera: makeCamera())
        let high = DepthSampler.columnPoints(around: [SIMD3(0.1, 0.3, -2)], radius: 0.15, betweenY: anywhere,
                                             depth: makeFrame(depth: 2), camera: makeCamera())

        #expect(low.count == 10 && low.count == high.count)
    }

    @Test("Only the chosen heights are kept")
    func onlyChosenHeights() {
        let points = DepthSampler.columnPoints(around: [SIMD3(0.1, 0, -2)], radius: 0.15, betweenY: 0...0.45,
                                               depth: makeFrame(depth: 2), camera: makeCamera())

        #expect(points.count == 2)
        #expect(points.allSatisfy { near($0.y, 0.3) || near($0.y, 0.1) })
    }

    @Test("The distance is measured across the floor: a wall behind the item is not part of it")
    func distanceAcrossTheFloor() {
        let points = DepthSampler.columnPoints(around: [SIMD3(0.1, 0, -2)], radius: 0.3, betweenY: anywhere,
                                               depth: makeFrame(depth: 3), camera: makeCamera())

        #expect(points.isEmpty)
    }

    @Test("The axis is a place in the room, not on the screen")
    func axisIsInTheRoom() {
        var pose = matrix_identity_float4x4
        pose.columns.3 = SIMD4(1, 0, 0, 1)

        let points = DepthSampler.columnPoints(around: [SIMD3(-0.25, 0, -2)], radius: 0.4, betweenY: anywhere,
                                               depth: makeFrame(depth: 2), camera: makeCamera(pose: pose))

        // World x = 0.2 x column - 0.9: columns 2...5 are within 0.4 m of x = -0.25.
        #expect(points.count == 40)
        #expect(points.allSatisfy { abs($0.x + 0.25) <= 0.4 + 1e-4 })
    }

    @Test("Two axes give two columns and nothing else")
    func twoAxes() {
        let points = DepthSampler.columnPoints(around: [SIMD3(-1.1, 0, -2), SIMD3(1.1, 0, -2)], radius: 0.05,
                                               betweenY: anywhere, depth: makeFrame(depth: 2), camera: makeCamera())

        #expect(points.count == 20)
    }

    @Test("Unusable depth is never kept")
    func unusableDepth() {
        for bad: Float in [0, -1, .nan, .infinity] {
            let points = DepthSampler.columnPoints(around: [.zero], radius: 0.3, betweenY: anywhere,
                                                   depth: makeFrame(depth: bad), camera: makeCamera())
            #expect(points.isEmpty)
        }
    }

    @Test("Pixels below the confidence asked for are skipped")
    func lowConfidenceSkipped() {
        let medium = makeFrame(depth: 2, confidence: 1)
        let anchor = [SIMD3<Float>(0.1, 0, -2)]

        #expect(DepthSampler.columnPoints(around: anchor, radius: 0.15, betweenY: anywhere, depth: medium,
                                          camera: makeCamera()).isEmpty)
        #expect(DepthSampler.columnPoints(around: anchor, radius: 0.15, betweenY: anywhere, depth: medium,
                                          camera: makeCamera(), minConfidence: 1).count == 10)
    }
}

/// The depth point a tap lands on: the nearest usable pixel, so a tap on a dark spot still finds a reading.
@Suite("Nearest depth point")
struct NearestPointTests {
    /// 20 x 10 depth map with every pixel unusable (depth 0), except the ones the test sets.
    private func emptyFrame(usable: [(column: Int, row: Int, confidence: UInt8)], depth: Float = 2) -> DepthFrame {
        var values = [Float](repeating: 0, count: 200)
        var confidence = [UInt8](repeating: 2, count: 200)
        for pixel in usable {
            values[pixel.row * 20 + pixel.column] = depth
            confidence[pixel.row * 20 + pixel.column] = pixel.confidence
        }
        return DepthFrame(width: 20, height: 10, depth: values, confidence: confidence)
    }

    /// The tap in picture fractions for the centre of depth pixel (column, row).
    private func tap(_ column: Int, _ row: Int) -> SIMD2<Float> {
        SIMD2((Float(column) + 0.5) / 20, (Float(row) + 0.5) / 10)
    }

    @Test("A tap on a good pixel gives that pixel's world point")
    func exactPixel() throws {
        let point = try #require(DepthSampler.nearestPoint(toNormalized: tap(10, 5), depth: makeFrame(depth: 2),
                                                           camera: makeCamera()))

        #expect(near(point, SIMD3(0.1, -0.1, -2)))
    }

    @Test("A tap on a hole takes the nearest usable pixel")
    func nearestUsable() throws {
        let frame = emptyFrame(usable: [(13, 5, 2), (8, 5, 2)])

        let point = try #require(DepthSampler.nearestPoint(toNormalized: tap(10, 5), depth: frame, camera: makeCamera()))

        // Column 8 is 2 pixels away, column 13 is 3: x = 0.2 x 8 - 1.9.
        #expect(near(point.x, -0.3))
    }

    @Test("At the same distance the higher confidence wins")
    func higherConfidenceWins() throws {
        let frame = emptyFrame(usable: [(8, 5, 1), (12, 5, 2)])

        let point = try #require(DepthSampler.nearestPoint(toNormalized: tap(10, 5), depth: frame, camera: makeCamera()))

        #expect(near(point.x, 0.5))
    }

    @Test("Nothing usable within the search radius gives nil, and low confidence does not count")
    func nothingUsable() {
        #expect(DepthSampler.nearestPoint(toNormalized: tap(10, 5), depth: emptyFrame(usable: [(16, 5, 2)]),
                                          camera: makeCamera()) == nil)
        #expect(DepthSampler.nearestPoint(toNormalized: tap(10, 5), depth: emptyFrame(usable: [(15, 5, 2)]),
                                          camera: makeCamera()) != nil)
        #expect(DepthSampler.nearestPoint(toNormalized: tap(10, 5), depth: emptyFrame(usable: [(10, 5, 0)]),
                                          camera: makeCamera()) == nil)
    }
}
