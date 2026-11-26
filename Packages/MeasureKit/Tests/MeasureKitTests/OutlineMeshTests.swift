import Foundation
import Testing
import simd
@testable import MeasureKit

// A10-106 case 22 and A10-121 case K7: each outline box is one mesh of corner marks (Amadeus, 21 and 26 Nov), with the
// thickness set when it is built (T1).

@Suite("A10-106 outline mesh")
struct OutlineMeshTests {
    @Test("K7: the mesh is the 24 arms of the padded box; every index is valid; nothing is near the middle of a long edge")
    func theMeshIsTheArmsOfThePaddedBox() throws {
        let box = WorldBox(min: SIMD3(0, 0, 0), max: SIMD3(0.2, 3, 0.2))
        let radius: Float = 0.004

        let geometry = OutlineMesh.geometry(of: box, radius: radius)

        #expect(geometry.armCount == 24)
        #expect(!geometry.positions.isEmpty)
        #expect(geometry.indices.count % 3 == 0)
        #expect(geometry.indices.allSatisfy { Int($0) < geometry.positions.count })
        // Every point is within the longest arm (12 cm) plus the radius of a corner of the padded box: the middle of the
        // 3 m edges stays empty.
        let padded = OutlineLayout.paddedBox(box)
        let corners = padded.corners
        let reach = OutlineLayout.cornerArmMax + radius + 1e-5
        #expect(geometry.positions.allSatisfy { point in corners.contains { simd_distance($0, point) <= reach } })
        // The arm length comes from the padded edges: x is 0.24 m padded, so its arm is 0.06 m (0.05 m unpadded).
        // The x arm at the padded box's min corner ends there, plus the radius of its round end.
        let nearTheMinCorner = geometry.positions.filter {
            abs($0.y - padded.min.y) <= 0.01 && abs($0.z - padded.min.z) <= 0.01 && $0.x < padded.min.x + 0.12
        }
        let armEnd = try #require(nearTheMinCorner.map(\.x).max())
        #expect(abs(armEnd - (padded.min.x + 0.06 + radius)) < 1e-4)
    }

    @Test("Case 22: a camera 2 m from the box centre, focal length 1000 pt, gives a 4 mm line radius")
    func radiusFromTheCameraDistance() {
        let box = WorldBox(min: SIMD3(-0.1, -0.1, -2.1), max: SIMD3(0.1, 0.1, -1.9))

        let radius = OutlineMesh.radius(for: box, cameraPosition: .zero, focalLength: 1000)

        #expect(abs(radius - 0.004) < 1e-6)
    }
}
