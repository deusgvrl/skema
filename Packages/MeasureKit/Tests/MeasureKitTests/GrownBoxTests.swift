import Foundation
import Testing
import simd
@testable import MeasureKit

// A10-106: the tap scan measures a light from its grown box. Cases 1–7 and 9–11 (Amadeus, 20 Nov); D24–D26 are the
// A10-90 rule E box cases, kept because WorldBox comes back with the same rules. Numbers are made-up geometry.

/// The makeCamera picture (200 x 100, f = 100) with a 100 x 50 depth map: one depth pixel is 2 picture pixels,
/// so at 2 m it is 4 cm wide. The two closures give each pixel's depth and confidence from its column and row.
private func depthMap(depth: (Int, Int) -> Float, confidence: (Int, Int) -> UInt8 = { _, _ in 2 }) -> DepthFrame {
    var depths: [Float] = [], confidences: [UInt8] = []
    for row in 0..<50 {
        for column in 0..<100 {
            depths.append(depth(column, row))
            confidences.append(confidence(column, row))
        }
    }
    return DepthFrame(width: 100, height: 50, depth: depths, confidence: confidences)
}

/// The middle of the picture, where the tap lands: depth pixel (50, 25).
private let middleTap = SIMD2<Float>(0.505, 0.51)
private let noFloor: Float = -100

@Suite("A10-106 paint from the tap")
struct PaintFromTapTests {
    @Test("Case 1: a 40 x 40 cm surface at 2.00 m in front of a wall at 3.00 m keeps only the surface")
    func keepsOnlyTheSurface() {
        // 10 x 10 depth pixels at 2 m = 40 x 40 cm; the tapped pixel (50, 25) is inside it.
        let frame = depthMap(depth: { column, row in (45..<55).contains(column) && (20..<30).contains(row) ? 2 : 3 })

        let points = DepthGrouping.surface(fromNormalized: middleTap, depth: frame, camera: makeCamera(), floorY: noFloor)

        #expect(points.count == 100)
        #expect(points.allSatisfy { near($0.z, -2) })
    }

    @Test("Case 2: a tilted head whose depth changes 1 cm on each pixel is kept whole")
    func keepsATiltedHead() {
        let frame = depthMap(depth: { column, _ in 2 + 0.01 * Float(column) })

        let points = DepthGrouping.surface(fromNormalized: middleTap, depth: frame, camera: makeCamera(), floorY: noFloor)

        #expect(points.count == 5000)
    }

    @Test("Case 3: a tap on an unsure pixel starts from a sure pixel 3 pixels away")
    func startsFromTheNearestSurePixel() {
        // Pixels closer than 3 pixels to (50, 25) are unsure (confidence 1): 25 of them (1 + 4 + 4 + 4 + 4 + 8).
        let unsure: (Int, Int) -> Bool = { column, row in (column - 50) * (column - 50) + (row - 25) * (row - 25) < 9 }
        let frame = depthMap(depth: { _, _ in 2 }, confidence: { column, row in unsure(column, row) ? 1 : 2 })

        let points = DepthGrouping.surface(fromNormalized: middleTap, depth: frame, camera: makeCamera(), floorY: noFloor)

        #expect(points.count == 5000 - 25)
    }

    @Test("Case 4: no sure pixel within 5 pixels of the tap gives no points, so no small box")
    func noSurePixelNearTheTap() {
        let frame = depthMap(depth: { _, _ in 2 },
                             confidence: { column, row in abs(column - 50) <= 5 && abs(row - 25) <= 5 ? 1 : 2 })

        let points = DepthGrouping.surface(fromNormalized: middleTap, depth: frame, camera: makeCamera(), floorY: noFloor)
        var measurements = ScanMeasurements()
        let light = UUID()
        measurements.addSurface(points: points, to: light, camera: makeCamera())

        #expect(points.isEmpty)
        #expect(measurements.bigBox(for: light) == nil)
    }

    @Test("Case 5: on a wall that reaches the floor, no point is lower than 3 cm above the floor")
    func stopsAboveTheFloor() {
        // A flat wall at 2 m: depth row r is at height (49 - 2r) x 2 cm, from +98 cm (top) to -98 cm (bottom).
        // With the floor at -50 cm, rows 0 to 36 (down to -46 cm) are 3 cm or more above it: 37 rows of 100.
        let frame = depthMap(depth: { _, _ in 2 })

        let points = DepthGrouping.surface(fromNormalized: middleTap, depth: frame, camera: makeCamera(), floorY: cm(-50))

        #expect(points.count == 3700)
        #expect(points.allSatisfy { $0.y >= cm(-47) - 1e-5 })
    }
}

/// 200 dots spread over a box given in centimetres, 10 on each face of each axis, so the 2%–98% box is exact.
private func dots(x: ClosedRange<Float>, y: ClosedRange<Float>, z: ClosedRange<Float>) -> [SIMD3<Float>] {
    func spread(_ range: ClosedRange<Float>) -> [Float] {
        let middle = (1...180).map { range.lowerBound + (range.upperBound - range.lowerBound) * Float($0) / 181 }
        return Array(repeating: range.lowerBound, count: 10) + middle + Array(repeating: range.upperBound, count: 10)
    }
    let xs = spread(x), ys = spread(y), zs = spread(z)
    return xs.indices.map { SIMD3(cm(xs[$0]), cm(ys[$0]), cm(zs[$0])) }
}

@Suite("A10-106 small and big boxes")
struct GrownBoxTests {
    @Test("Case D24: evenly spread dots over 40 x 60 x 10 cm give a box of about that size, give or take 3 cm")
    func smallBoxMatchesTheDots() throws {
        let even = (0..<201).map { index -> SIMD3<Float> in
            let share = Float(index) / 200
            return SIMD3(cm(40 * share), cm(60 * share), cm(10 * share))
        }
        let box = try #require(WorldBox.around(even))
        let size = box.max - box.min
        #expect(abs(size.x - cm(40)) <= cm(3))
        #expect(abs(size.y - cm(60)) <= cm(3))
        #expect(abs(size.z - cm(10)) <= cm(3))
    }

    @Test("Case D25: one stray dot 1 m behind is not counted, the box stays 10 cm deep")
    func strayDotIsIgnored() throws {
        let box = try #require(WorldBox.around(dots(x: 0...40, y: 0...60, z: 0...10) + [SIMD3(cm(20), cm(30), cm(110))]))
        #expect(abs((box.max.z - box.min.z) - cm(10)) <= cm(2))
    }

    @Test("Case D26: dots all at one depth give a box 2 cm deep, centred on them")
    func flatDotsGetTwoCentimetresDepth() throws {
        let box = try #require(WorldBox.around(dots(x: 0...40, y: 0...60, z: 50...50)))
        #expect(near(box.max.z - box.min.z, cm(2)))
        #expect(near((box.max.z + box.min.z) / 2, cm(50)))
    }

    @Test("Case 6: 19 points make no small box; 20 points make one")
    func twentyPointsMakeABox() {
        var measurements = ScanMeasurements()
        let few = UUID(), enough = UUID()
        let points = dots(x: 0...40, y: 0...60, z: -210 ... -200)

        measurements.addSurface(points: Array(points.prefix(19)), to: few, camera: makeCamera())
        measurements.addSurface(points: Array(points.prefix(20)), to: enough, camera: makeCamera())

        #expect(measurements.bigBox(for: few) == nil)
        #expect(measurements.bigBox(for: enough) != nil)
    }

    // 27 Nov: the big box is no longer the union of the newest 30 frames' boxes, which one bad frame could stretch
    // for 30 frames. It is the box of all the light's points, a frame far bigger than the usual ones is left out, and
    // the outline only uses the spots seen in the newest 30 frames.

    @Test("Case 7: one frame far bigger than the usual ones (a leak) is left out of the box")
    func bigFrameIsLeftOut() throws {
        var measurements = ScanMeasurements()
        let light = UUID()
        for _ in 0..<6 {
            measurements.addFrame(dots(x: -10...40, y: 0...50, z: -250 ... -200), to: light, kind: .light,
                                  camera: makeCamera())
        }
        // This frame reaches 1.5 m to the left: more than twice the usual 50 cm.
        let added = measurements.addFrame(dots(x: -150...40, y: 0...50, z: -250 ... -200), to: light, kind: .light,
                                          camera: makeCamera())

        #expect(!added)
        let box = try #require(measurements.bigBox(for: light))
        #expect(near(box.min.x, cm(-10), cm(3)) && near(box.max.x, cm(40), cm(3)))
    }

    @Test("Case 7b: the outline lets go of spots not seen in the newest 30 frames; the big box keeps them")
    func outlineFollowsTheNewestFrames() throws {
        var measurements = ScanMeasurements()
        let light = UUID()
        for _ in 0..<5 {
            measurements.addFrame(dots(x: -10...40, y: 0...50, z: -250 ... -200), to: light, kind: .light,
                                  camera: makeCamera())
        }
        // The item now shows 30 cm further right (ARKit's world moved) for the next 30 frames.
        for _ in 0..<30 {
            measurements.addFrame(dots(x: 20...70, y: 0...50, z: -250 ... -200), to: light, kind: .light,
                                  camera: makeCamera())
        }

        let outline = try #require(measurements.outline(for: light))
        #expect(near(outline.min.x, cm(20), cm(3)), "Outline: \(outline)")
        #expect(near(try #require(measurements.bigBox(for: light)).min.x, cm(-10), cm(3)))
    }
}

@Suite("A10-106 height and position from the back of the big box")
struct BackOfTheBoxTests {
    private let light = UUID(), subject = UUID()

    /// The light's front and back faces: a 2 cm grid over 180–220 cm (x) and 110–170 cm (y), at z = -20 and 20 cm.
    /// 1,302 points in different 1 cm cells, so the light is measured, and its box is exactly those extents.
    private let lightFaces: [SIMD3<Float>] = [Float(-20), 20].flatMap { z in
        stride(from: Float(180), through: 220, by: 2).flatMap { x in
            stride(from: Float(110), through: 170, by: 2).map { y in SIMD3(cm(x), cm(y), cm(z)) }
        }
    }

    /// A subject standing on the floor (y = 0) at (x, z) in centimetres, and a light whose box runs 180–220 cm in x,
    /// 110–170 cm high, and -20 to 20 cm in z: 40 cm deep, its centre 2.00 m from a subject at (0, 0).
    private func measurements(subjectAt x: Float, _ z: Float) -> ScanMeasurements {
        var measurements = ScanMeasurements()
        // A 20 x 20 cm block, 50 cm high, on a 2 cm grid: 3,146 points in different 1 cm cells, base centre (x, z).
        let block = stride(from: Float(-10), through: 10, by: 2).flatMap { dx in
            stride(from: Float(-10), through: 10, by: 2).flatMap { dz in
                stride(from: Float(0), through: 50, by: 2).map { y in SIMD3(cm(x + dx), cm(y), cm(z + dz)) }
            }
        }
        measurements.add(points: block, to: subject, camera: makeCamera())
        measurements.addSurface(points: lightFaces, to: light, camera: makeCamera())
        return measurements
    }

    @Test("Case 9: the back point is 2.20 m from the subject, and that is the distance")
    func distanceToTheBackPoint() throws {
        let result = try #require(measurements(subjectAt: 0, 0).results(subject: subject, floorY: 0)[light])

        #expect(result.status == .measured)
        #expect(near(try #require(result.distanceToSubject), cm(220)))
        #expect(near(try #require(result.floorOffset), SIMD2(cm(220), 0)))
    }

    @Test("Case 10: a big box from 110 to 170 cm above the floor gives a height of 140 cm")
    func middleHeight() throws {
        let result = try #require(measurements(subjectAt: 0, 0).results(subject: subject, floorY: 0)[light])

        #expect(near(try #require(result.height), cm(140)))
    }

    @Test("Case 11: when the subject moves 50 cm, the back point and the distance are worked out again")
    func subjectMoves() throws {
        // Subject at (0, 50 cm): from it to the box centre (200, 0) is the direction (2, -0.5). Walking from the centre
        // that way, the box's x edge (220) comes first, after 20.6 cm: the back point is (220, -5) cm,
        // and the distance is the length of (220, -55) cm: 226.8 cm.
        let result = try #require(measurements(subjectAt: 0, 50).results(subject: subject, floorY: 0)[light])

        #expect(near(try #require(result.floorOffset), SIMD2(cm(220), cm(-55)), 1e-3))
        #expect(near(try #require(result.distanceToSubject), cm(226.77), 1e-3))
    }
}
