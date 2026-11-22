import Foundation
import Testing
import simd
@testable import MeasureKit

// A10-106 cases 21–22: each outline box is one mesh (Amadeus, 21 Nov), with the thickness set when it is built (T1).

@Suite("A10-106 outline mesh")
struct OutlineMeshTests {
    @Test("Case 21: a 10 cm box gives 12 dashes in one geometry; every index is valid; every point is near the box")
    func oneGeometryForTheBox() {
        let box = WorldBox(min: SIMD3(0, 0, 0), max: SIMD3(0.1, 0.1, 0.1))
        let radius: Float = 0.004

        let geometry = OutlineMesh.geometry(of: box, radius: radius)

        // Each 10 cm edge holds one dash (0–6 cm); 12 edges.
        #expect(geometry.dashCount == 12)
        #expect(!geometry.positions.isEmpty)
        #expect(geometry.indices.count % 3 == 0)
        #expect(geometry.indices.allSatisfy { Int($0) < geometry.positions.count })
        let low = box.min - SIMD3(repeating: radius + 1e-5), high = box.max + SIMD3(repeating: radius + 1e-5)
        #expect(geometry.positions.allSatisfy { all($0 .>= low) && all($0 .<= high) })
    }

    @Test("Case 21: every dash has the same number of points and triangles")
    func dashesAreAlike() {
        let one = OutlineMesh.geometry(of: WorldBox(min: .zero, max: SIMD3(0.1, 0.1, 0.1)), radius: 0.004)
        // A 25 cm cube: 3 dashes per edge (0–6, 10–16, 20–25), 36 in all.
        let three = OutlineMesh.geometry(of: WorldBox(min: .zero, max: SIMD3(0.25, 0.25, 0.25)), radius: 0.004)

        #expect(three.dashCount == 36)
        #expect(three.positions.count == one.positions.count * 3)
        #expect(three.indices.count == one.indices.count * 3)
    }

    @Test("Case 22: a camera 2 m from the box centre, focal length 1000 pt, gives a 4 mm line radius")
    func radiusFromTheCameraDistance() {
        let box = WorldBox(min: SIMD3(-0.1, -0.1, -2.1), max: SIMD3(0.1, 0.1, -1.9))

        let radius = OutlineMesh.radius(for: box, cameraPosition: .zero, focalLength: 1000)

        #expect(abs(radius - 0.004) < 1e-6)
    }
}
