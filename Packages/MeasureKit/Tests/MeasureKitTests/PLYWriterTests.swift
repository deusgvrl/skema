import Testing
import Foundation
import simd
@testable import MeasureKit

@Suite struct PLYWriterTests {
    private let header = "ply\nformat binary_little_endian 1.0\nelement vertex 2\n"
        + "property float x\nproperty float y\nproperty float z\n"
        + "property uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n"

    @Test func headerSizeAndFirstVertex() throws {
        let pts: [(world: SIMD3<Float>, rgb: SIMD3<UInt8>)] = [
            (SIMD3(1.5, -2.25, 3), SIMD3(10, 20, 30)), (SIMD3(0, 0, 0), SIMD3(255, 0, 1))]
        let data = PLYWriter.binary(pts)
        let headerBytes = Data(header.utf8)
        #expect(data.prefix(headerBytes.count) == headerBytes)
        #expect(data.count == headerBytes.count + 2 * 15)

        let v = data.dropFirst(headerBytes.count)
        try #require(v.count >= 15)
        let floats = (0..<3).map { k in
            v.dropFirst(k * 4).prefix(4).withUnsafeBytes { Float(bitPattern: UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        }
        #expect(floats == [1.5, -2.25, 3])
        #expect(Array(v.dropFirst(12).prefix(3)) == [10, 20, 30])
    }

    @Test func emptyCloudIsHeaderOnly() {
        let data = PLYWriter.binary([])
        #expect(String(decoding: data, as: UTF8.self).contains("element vertex 0\n"))
        #expect(String(decoding: data, as: UTF8.self).hasSuffix("end_header\n"))
    }
}
