import Foundation
import Testing
import simd
@testable import MeasureKit

// A10-106 commit 7 (Amadeus, 21 Nov): an item with a big box is measured from the box, so its results need only how
// many points it has, not the head maths over every point (Time Profiler after commit 6: that maths was most of our
// CPU, and its answer was thrown away). Cases 26–29. Numbers are made-up geometry.

/// `count` points on a flat grid 2 cm apart, each in its own 1 cm cell, starting at 180 cm (x) and 110 cm (y),
/// 20 points to a row, at depth `z` cm.
private func grid(_ count: Int, z: Float = 0.5) -> [SIMD3<Float>] {
    (0..<count).map { index in
        SIMD3(cm(180.5 + 2 * Float(index % 20)), cm(110.5 + 2 * Float(index / 20)), cm(z))
    }
}

@Suite("A10-106 results of an item with a big box")
struct BigBoxResultsTests {
    private let light = UUID(), subject = UUID()

    @Test("Case 26: a light with a big box and 99 points has too few points; with 100 points it is measured")
    func pointCountDecidesTheStatus() throws {
        var few = ScanMeasurements(), enough = ScanMeasurements()
        few.addSurface(points: grid(99), to: light, camera: makeCamera())
        enough.addSurface(points: grid(100), to: light, camera: makeCamera())

        #expect(few.bigBox(for: light) != nil)
        #expect(try #require(few.results(subject: subject, floorY: 0)[light]).status == .tooFewPoints)
        #expect(try #require(enough.results(subject: subject, floorY: 0)[light]).status == .measured)
    }

    @Test("Case 27: a light with a big box whose points were only seen farther than 5 m is out of range")
    func farPointsAreOutOfRange() throws {
        var measurements = ScanMeasurements()
        // 8 m in front of the camera: the box is made, but every point is beyond DepthSampler.maxRange.
        measurements.addSurface(points: grid(200, z: -800), to: light, camera: makeCamera())

        #expect(measurements.bigBox(for: light) != nil)
        #expect(try #require(measurements.results(subject: subject, floorY: 0)[light]).status == .outOfRange)
    }

    @Test("Case 28: a light with a stand and a head is measured from the back of its big box, as before")
    func standAndHeadUseTheBox() throws {
        var measurements = ScanMeasurements()
        // The head: front and back faces, 180–220 cm (x), 110–170 cm (y), z = -20 and 20 cm. Its box is those extents.
        let head: [SIMD3<Float>] = [Float(-20), 20].flatMap { z in
            stride(from: Float(180), through: 220, by: 2).flatMap { x in
                stride(from: Float(110), through: 170, by: 2).map { y in SIMD3(cm(x), cm(y), cm(z)) }
            }
        }
        // The stand: a thin column under the head, 0–108 cm high, added as points only (it makes no box).
        let stand = stride(from: Float(0.5), through: 108, by: 1).flatMap { y in
            [Float(199.5), 200.5].map { x in SIMD3(cm(x), cm(y), cm(0.5)) }
        }
        // A 20 x 20 cm subject block, 50 cm high, standing at (0, 0).
        let block = stride(from: Float(-10), through: 10, by: 2).flatMap { dx in
            stride(from: Float(-10), through: 10, by: 2).flatMap { dz in
                stride(from: Float(0), through: 50, by: 2).map { y in SIMD3(cm(dx), cm(y), cm(dz)) }
            }
        }
        measurements.add(points: block, to: subject, camera: makeCamera())
        measurements.addSurface(points: head, to: light, camera: makeCamera())
        measurements.add(points: stand, to: light, camera: makeCamera())

        let result = try #require(measurements.results(subject: subject, floorY: 0)[light])

        #expect(result.status == .measured)
        #expect(near(try #require(result.height), cm(140)))
        #expect(near(try #require(result.distanceToSubject), cm(220)))
    }

    @Test("Case 29: the results of a light with a big box and 200,000 points take less than 5 ms")
    func manyPointsAreFast() throws {
        var measurements = ScanMeasurements()
        // A 1 x 1 m x 20 cm block of points 1 cm apart, each in its own cell: 100 x 100 x 20 = 200,000.
        let points = (0..<100).flatMap { x in
            (0..<100).flatMap { y in
                (0..<20).map { z in SIMD3(cm(150.5 + Float(x)), cm(100.5 + Float(y)), cm(-9.5 + Float(z))) }
            }
        }
        measurements.addSurface(points: points, to: light, camera: makeCamera())
        #expect(measurements.bigBox(for: light) != nil)

        let clock = ContinuousClock()
        var result: EquipmentResult?
        let time = clock.measure { result = measurements.results(subject: subject, floorY: 0)[light] }

        #expect(result?.status == .measured)
        #expect(time < .milliseconds(5), "results took \(time)")
    }
}
