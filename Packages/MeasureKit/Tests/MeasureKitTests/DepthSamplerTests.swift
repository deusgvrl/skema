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
