//
//  EquipmentSightingsTests.swift
//  Skema Tests
//
//  A10-62 connector cases C1–C7: a detection's mask + the LiDAR depth → a 3D sighting for tracking.
//  Camera: 1920 x 1440 picture, fx = fy = 1000, centre (960, 720), at the origin looking along -z.
//  Depth map: 8 x 6. Its pixel centres sit evenly around the picture centre, so with the same depth
//  everywhere the middle point of the sampled points is straight ahead.
//

import MeasureKit
import simd
import Testing
@testable import Final_Challenge_App

private let camera: CameraModel = {
    var intrinsics = matrix_identity_float3x3
    intrinsics[0][0] = 1000
    intrinsics[1][1] = 1000
    intrinsics[2][0] = 960
    intrinsics[2][1] = 720
    return CameraModel(intrinsics: intrinsics, imageResolution: SIMD2(1920, 1440),
                       cameraToWorld: matrix_identity_float4x4)
}()

private func depth(metres: Float, confidence: UInt8 = 2) -> DepthFrame {
    DepthFrame(width: 8, height: 6, depth: [Float](repeating: metres, count: 48),
               confidence: [UInt8](repeating: confidence, count: 48))
}

private let fullMask = InstanceMask(width: 640, height: 640, pixels: [UInt8](repeating: 1, count: 640 * 640))

/// A 4 x 4 patch in the middle of a 640 x 640 mask: too small to hold 20 depth points.
private let tinyMask: InstanceMask = {
    var pixels = [UInt8](repeating: 0, count: 640 * 640)
    for row in 318..<322 { for column in 318..<322 { pixels[row * 640 + column] = 1 } }
    return InstanceMask(width: 640, height: 640, pixels: pixels)
}()

private func detection(_ kind: EquipmentKind, mask: InstanceMask = fullMask,
                       confidence: Float = 0.6) -> EquipmentDetection {
    EquipmentDetection(kind: kind, confidence: confidence, mask: mask)
}

@Suite("Equipment sightings")
struct EquipmentSightingsTests {
    @Test("Case C1: a camera mask over a surface 2 m away gives a sighting 2 m straight ahead")
    func cameraTwoMetresAhead() throws {
        let made = EquipmentSightings.make(from: [detection(.camera, confidence: 0.7)], depth: depth(metres: 2),
                                           camera: camera)
        let sighting = try #require(made.first?.sighting)
        #expect(simd_distance(sighting.position, SIMD3(0, 0, -2)) < 1e-4)
        #expect(sighting.label == "camera")
        #expect(sighting.confidence == 0.7)
    }

    @Test("Case C2: a studio lighting detection keeps its label")
    func lightKeepsLabel() {
        let made = EquipmentSightings.make(from: [detection(.studioLighting)], depth: depth(metres: 2), camera: camera)
        #expect(made.map(\.sighting.label) == ["studio lighting"])
    }

    @Test("Case C3: a tiny mask gives no sighting")
    func tinyMaskGivesNothing() {
        let made = EquipmentSightings.make(from: [detection(.camera, mask: tinyMask)], depth: depth(metres: 2),
                                           camera: camera)
        #expect(made.isEmpty)
    }

    @Test("Case C4: low-confidence depth gives no sighting")
    func lowConfidenceGivesNothing() {
        let made = EquipmentSightings.make(from: [detection(.camera)], depth: depth(metres: 2, confidence: 0),
                                           camera: camera)
        #expect(made.isEmpty)
    }

    @Test("Case C5: a frame without depth gives no sightings and no crash")
    func noDepthGivesNothing() {
        #expect(EquipmentSightings.make(from: [detection(.camera)], depth: nil, camera: camera).isEmpty)
    }

    @Test("Case C6: something 7 m away, past the 5 m limit, gives no sighting")
    func tooFarGivesNothing() {
        let made = EquipmentSightings.make(from: [detection(.camera)], depth: depth(metres: 7), camera: camera)
        #expect(made.isEmpty)
    }

    @Test("Case C7: each sighting stays paired with its own detection's mask, in order")
    func sightingsStayPairedWithTheirMasks() {
        let left = InstanceMask(width: 640, height: 640, pixels: (0..<640 * 640).map { $0 % 640 < 320 ? 1 : 0 })
        let right = InstanceMask(width: 640, height: 640, pixels: (0..<640 * 640).map { $0 % 640 < 320 ? 0 : 1 })
        let detections = [detection(.camera, mask: left), detection(.camera, mask: tinyMask),
                          detection(.studioLighting, mask: right)]
        let made = EquipmentSightings.make(from: detections, depth: depth(metres: 2), camera: camera)
        #expect(made.map(\.mask) == [left, right])
        #expect(made.map(\.sighting.label) == ["camera", "studio lighting"])
    }
}
