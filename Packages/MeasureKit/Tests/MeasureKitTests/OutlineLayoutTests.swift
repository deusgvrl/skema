import Foundation
import Testing
import simd
@testable import MeasureKit

// A10-106 cases 17–19: the maths of the 3D outline box (Amadeus, 21 Nov). The drawing itself is checked by hand.

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

    @Test("Case 18: a 45 cm edge gets dashes at 0–6, 10–16, 20–26, 30–36 and 40–45 cm")
    func dashLayout() {
        let dashes = OutlineLayout.dashes(from: SIMD3(0, 0, 0), to: SIMD3(0.45, 0, 0), dash: 0.06, gap: 0.04)

        let spans = dashes.map { [($0.start.x * 100).rounded(), ($0.end.x * 100).rounded()] }
        #expect(spans == [[0, 6], [10, 16], [20, 26], [30, 36], [40, 45]])
    }

    @Test("Case 18: dashes follow the edge's direction, here down the y axis")
    func dashesFollowTheEdge() throws {
        let dashes = OutlineLayout.dashes(from: SIMD3(1, 0.2, 0), to: SIMD3(1, 0, 0), dash: 0.06, gap: 0.04)

        try #require(dashes.count == 2)
        #expect(dashes.allSatisfy { $0.start.x == 1 && $0.end.x == 1 && $0.start.z == 0 })
        #expect(abs(dashes[0].start.y - 0.2) < 1e-6 && abs(dashes[0].end.y - 0.14) < 1e-6)
        #expect(abs(dashes[1].start.y - 0.1) < 1e-6 && abs(dashes[1].end.y - 0.04) < 1e-6)
    }

    @Test("Case 19: with a 1000 pt focal length, a 4 pt line has a 4 mm radius at 2 m and 8 mm at 4 m")
    func radiusForFourPoints() {
        #expect(abs(OutlineLayout.radius(thickness: 4, distance: 2, focalLength: 1000) - 0.004) < 1e-7)
        #expect(abs(OutlineLayout.radius(thickness: 4, distance: 4, focalLength: 1000) - 0.008) < 1e-7)
    }
}
