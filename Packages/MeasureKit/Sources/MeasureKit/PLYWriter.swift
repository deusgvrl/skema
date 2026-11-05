import Foundation
import simd

public enum PLYWriter {
    /// Binary little-endian PLY: "element vertex N" with float x,y,z and uchar red,green,blue.
    public static func binary(_ points: [(world: SIMD3<Float>, rgb: SIMD3<UInt8>)]) -> Data {
        let header = "ply\nformat binary_little_endian 1.0\nelement vertex \(points.count)\n"
            + "property float x\nproperty float y\nproperty float z\n"
            + "property uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n"
        var data = Data(header.utf8)
        data.reserveCapacity(data.count + points.count * 15)
        for p in points {
            for v in [p.world.x, p.world.y, p.world.z] {
                withUnsafeBytes(of: v.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            }
            data.append(contentsOf: [p.rgb.x, p.rgb.y, p.rgb.z])
        }
        return data
    }
}
