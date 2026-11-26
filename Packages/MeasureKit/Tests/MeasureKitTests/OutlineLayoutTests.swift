import Foundation
import Testing
import simd
@testable import MeasureKit

// A10-106 cases 17 and 19, and A10-121 cases K1–K6: the maths of the 3D outline box (Amadeus, 21 and 26 Nov). The drawing
// itself is checked by hand.

@Suite("A10-106 outline layout")
struct OutlineLayoutTests {
    @Test("Case 17: a world box has 12 edges, each between two corners that differ on one axis")
    func twelveEdges() {
        let box = WorldBox(min: SIMD3(0, 0, 0), max: SIMD3(1, 2, 3))

        let edges = box.edges

        #expect(edges.count == 12)
        for edge in edges {
            let differs = (0..<3).filter { edge.start[$0] != edge.end[$0] }
            #expect(differs.count == 1)
        }
        // 4 edges run along each axis: 4 of length 1 (x), 4 of length 2 (y), 4 of length 3 (z).
        let lengths = edges.map { simd_distance($0.start, $0.end) }.sorted()
        #expect(lengths == [1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3])
    }

    @Test("K1: the padded box grows 2 cm on every side except the bottom")
    func thePaddedBoxGrowsTwoCentimetresExceptAtTheBottom() {
        let box = WorldBox(min: SIMD3(0, 0, 0), max: SIMD3(1, 2, 3))

        let padded = OutlineLayout.paddedBox(box)

        #expect(padded.min == SIMD3(-0.02, 0, -0.02))
        #expect(padded.max == SIMD3(1.02, 2.02, 3.02))
    }

    @Test("K2: an arm is a quarter of its edge: 40 cm gives 10 cm")
    func anArmIsAQuarterOfItsEdge() {
        #expect(abs(OutlineLayout.armLength(ofEdge: 0.40) - 0.10) < 1e-6)
    }

    @Test("K3: an arm is at least 3 cm: an 8 cm edge gives 3 cm")
    func anArmIsAtLeastThreeCentimetres() {
        #expect(abs(OutlineLayout.armLength(ofEdge: 0.08) - 0.03) < 1e-6)
    }

    @Test("K4: an arm is at most 12 cm: a 2 m edge gives 12 cm")
    func anArmIsAtMostTwelveCentimetres() {
        #expect(abs(OutlineLayout.armLength(ofEdge: 2.0) - 0.12) < 1e-6)
    }

    @Test("K5: an arm is never longer than half its edge: a 4 cm edge gives 2 cm")
    func anArmIsNeverLongerThanHalfItsEdge() {
        #expect(abs(OutlineLayout.armLength(ofEdge: 0.04) - 0.02) < 1e-6)
    }

    @Test("K6: a box has 3 arms at each of its 8 corners, pointing into the box, each with its own edge's arm length")
    func aBoxHasThreeArmsAtEachCorner() {
        let box = WorldBox(min: SIMD3(0, 0, 0), max: SIMD3(0.4, 2, 0.08))
        // The arm length per axis: x 0.10 (a quarter), y 0.12 (the maximum), z 0.03 (the minimum).
        let lengths: [Float] = [0.10, 0.12, 0.03]

        let arms = OutlineLayout.cornerArms(of: box)

        #expect(arms.count == 24)
        var perCorner: [SIMD3<Float>: Int] = [:]
        var axesPerCorner: [SIMD3<Float>: Set<Int>] = [:]
        for arm in arms {
            let atCorner = (0..<3).allSatisfy { arm.start[$0] == box.min[$0] || arm.start[$0] == box.max[$0] }
            #expect(atCorner)
            perCorner[arm.start, default: 0] += 1
            let axes = (0..<3).filter { arm.start[$0] != arm.end[$0] }
            guard axes.count == 1, let axis = axes.first else {
                Issue.record("An arm must differ from its start on exactly one axis.")
                continue
            }
            axesPerCorner[arm.start, default: []].insert(axis)
            let towardsTheMiddle: Float = arm.start[axis] == box.min[axis] ? 1 : -1
            #expect(abs((arm.end[axis] - arm.start[axis]) - towardsTheMiddle * lengths[axis]) < 1e-6)
        }
        #expect(perCorner.count == 8)
        #expect(perCorner.values.allSatisfy { $0 == 3 })
        // One arm along each axis at every corner, not three along the same one.
        #expect(axesPerCorner.values.allSatisfy { $0 == [0, 1, 2] })
    }

    @Test("Case 19: with a 1000 pt focal length, a 4 pt line has a 4 mm radius at 2 m and 8 mm at 4 m")
    func radiusForFourPoints() {
        #expect(abs(OutlineLayout.radius(thickness: 4, distance: 2, focalLength: 1000) - 0.004) < 1e-7)
        #expect(abs(OutlineLayout.radius(thickness: 4, distance: 4, focalLength: 1000) - 0.008) < 1e-7)
    }
}
