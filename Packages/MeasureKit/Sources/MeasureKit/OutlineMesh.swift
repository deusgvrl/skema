import simd

/// The triangles of one outline box (A10-106, 21 Nov): the corner arms of the box in one list, so RealityKit draws the
/// whole box as one mesh instead of about 1,500 entities. Pure maths, so it can be made off the main actor.
public struct OutlineGeometry: Sendable, Equatable {
    public var positions: [SIMD3<Float>] = []
    /// Three per triangle, each an index into `positions`.
    public var indices: [UInt32] = []
    public var armCount = 0
}

public enum OutlineMesh {
    /// Points around an arm's tube.
    public static let sides = 8
    /// Rings that round each end of an arm, from its tip to the tube.
    public static let capRings = 2

    /// A10-121 case K7: the 24 corner arms (`OutlineLayout.cornerArms`) of the padded box (`OutlineLayout.paddedBox`),
    /// each as a tube of `radius` with round ends, all in one geometry.
    public static func geometry(of box: WorldBox, radius: Float) -> OutlineGeometry {
        var geometry = OutlineGeometry()
        for arm in OutlineLayout.cornerArms(of: OutlineLayout.paddedBox(box)) {
            appendTube(from: arm.start, to: arm.end, radius: radius, to: &geometry)
        }
        return geometry
    }

    /// A10-106 case 22 (thickness T1): the radius that makes the lines `OutlineLayout.thickness` points thick when the
    /// box is seen from `cameraPosition`, measured to the box centre.
    public static func radius(for box: WorldBox, cameraPosition: SIMD3<Float>, focalLength: Float) -> Float {
        OutlineLayout.radius(distance: simd_distance(cameraPosition, (box.min + box.max) / 2), focalLength: focalLength)
    }

    /// One arm: a tip point, `capRings` rings that widen to the tube at `start`, the same rings narrowing after
    /// `end`, and the other tip. Neighbouring rings are joined by quads (two triangles); each tip by a fan.
    private static func appendTube(from start: SIMD3<Float>, to end: SIMD3<Float>, radius: Float,
                                   to geometry: inout OutlineGeometry) {
        let length = simd_distance(start, end)
        guard length > 0 else { return }
        let axis = (end - start) / length
        let helper: SIMD3<Float> = abs(axis.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
        let across = simd_normalize(simd_cross(axis, helper))
        let up = simd_cross(axis, across)
        let first = UInt32(geometry.positions.count)

        // Rings from the start tip to the end tip: latitude from the tip (0) to the tube (pi/2), and back.
        let latitudes = (1...capRings).map { Float.pi / 2 * Float($0) / Float(capRings) }
        var rings: [(centre: SIMD3<Float>, size: Float)] = latitudes.map { (start - axis * radius * cos($0), radius * sin($0)) }
        rings += latitudes.reversed().map { (end + axis * radius * cos($0), radius * sin($0)) }

        geometry.positions.append(start - axis * radius)                       // start tip
        for ring in rings {
            for side in 0..<sides {
                let angle = 2 * Float.pi * Float(side) / Float(sides)
                geometry.positions.append(ring.centre + (across * cos(angle) + up * sin(angle)) * ring.size)
            }
        }
        geometry.positions.append(end + axis * radius)                         // end tip

        let sideCount = UInt32(sides)
        func ringPoint(_ ring: Int, _ side: Int) -> UInt32 { first + 1 + UInt32(ring) * sideCount + UInt32(side % sides) }
        let endTip = first + 1 + UInt32(rings.count) * sideCount
        for side in 0..<sides {
            geometry.indices += [first, ringPoint(0, side + 1), ringPoint(0, side)]
            geometry.indices += [endTip, ringPoint(rings.count - 1, side), ringPoint(rings.count - 1, side + 1)]
            for ring in 0..<(rings.count - 1) {
                geometry.indices += [ringPoint(ring, side), ringPoint(ring, side + 1), ringPoint(ring + 1, side + 1)]
                geometry.indices += [ringPoint(ring, side), ringPoint(ring + 1, side + 1), ringPoint(ring + 1, side)]
            }
        }
        geometry.armCount += 1
    }
}
