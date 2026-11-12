//
//  EquipmentDetectorTests.swift
//  Skema Tests
//
//  A10-60 test cases 1, 2, 8, 9, 11 and 12 (docs/test-cases/A10-60_equipment-detector.md in the Challenge 5 folder).
//  Cases 3–7 and 10 are in MeasureKit (EquipmentFilterTests, MaskUpsampleTests). Case 13 waits for mini-setup photos.
//

import CoreML
import CoreVideo
import Foundation
import MeasureKit
import MeasureKitVision
import simd
import Testing
@testable import Final_Challenge_App

/// The bundled model is large, so it is loaded once and shared.
private enum BundledDetector {
    static let shared: Result<EquipmentDetector, Error> = Result { try EquipmentDetector() }
}

private func greyFrame() throws -> ScanFrame {
    let image = try makePixelBuffer(width: 256, height: 192, format: kCVPixelFormatType_32BGRA,
                                    values: [UInt32](repeating: 0xFF80_8080, count: 256 * 192))
    return ScanFrame(
        timestamp: 0, image: image, orientation: .right,
        camera: CameraModel(intrinsics: matrix_identity_float3x3, imageResolution: SIMD2(256, 192),
                            cameraToWorld: matrix_identity_float4x4),
        depth: nil, tracking: .normal, ambientIntensity: nil, planes: []
    )
}

/// Shared yes/no flags for case 11, only touched on the main actor.
@MainActor private final class MainActorFlags {
    var tickedDuringDetect = false
    var detectFinished = false
}

@Suite("Equipment detector")
struct EquipmentDetectorTests {
    @Test("Case 1: the bundled model loads and knows exactly studio lighting and camera")
    func modelLoadsWithTheTwoKinds() throws {
        let detector = try BundledDetector.shared.get()
        #expect(Set(detector.promptCounts.keys) == [.studioLighting, .camera])
    }

    @Test("Case 2: 20 prompts are studio lighting and 3 are camera")
    func promptCountsPerKind() throws {
        let detector = try BundledDetector.shared.get()
        #expect(detector.promptCounts == [.studioLighting: 20, .camera: 3])
    }

    @Test("Model labels are normalized: spaces and capitals don't matter, other labels are unknown")
    func kindFromModelLabel() {
        #expect(EquipmentKind(modelLabel: " Studio Lighting") == .studioLighting)
        #expect(EquipmentKind(modelLabel: "CAMERA ") == .camera)
        #expect(EquipmentKind(modelLabel: "tripod") == nil)
    }

    @Test("Case 8: an empty grey picture gives no detections and no crash")
    func greyFrameGivesNothing() async throws {
        let detector = try BundledDetector.shared.get()
        let detections = try await detector.detect(in: try greyFrame())
        #expect(detections.isEmpty)
    }

    // Case 9, through the decoding seam with hand-made model output: one prompt row per kind,
    // one prototype that is +1 everywhere, so each mask is exactly its box at 640 x 640.
    // Class 0 is a light prompt, class 1 a camera prompt.
    @Test("Case 9: every detection has a kind, a confidence and a 640 x 640 mask inside its box")
    func detectionsCarryKindConfidenceAndMask() {
        let names: [Int: String] = [0: "studio lighting", 1: "camera"]
        let light = YOLORow(x1: 0, y1: 0, x2: 100, y2: 100, confidence: 0.9, classIndex: 0, coefficients: [1])
        let camera = YOLORow(x1: 300, y1: 300, x2: 340, y2: 320, confidence: 0.6, classIndex: 1, coefficients: [1])
        let protos = [Float](repeating: 1, count: 160 * 160)

        let detections = EquipmentDetector.detections(from: [camera, light], protos: protos, protoSize: 160,
                                                      classNames: names, orientation: .up)

        #expect(detections.map(\.kind) == [.studioLighting, .camera])
        #expect(detections.map(\.confidence) == [0.9, 0.6])
        #expect(detections.allSatisfy { $0.mask.width == 640 && $0.mask.height == 640 })
        #expect(detections.map { $0.mask.pixels.reduce(0) { $0 + Int($1) } } == [100 * 100, 40 * 20])
    }

    @Test("Case 11 (smoke): detect runs from a background task and returns")
    func detectRunsInTheBackground() async throws {
        let detector = try BundledDetector.shared.get()
        let frame = try greyFrame()
        let detections = try await Task.detached { try await detector.detect(in: frame) }.value
        #expect(detections.isEmpty)
    }

    // Case 11. Called from the main actor (as a ViewModel does), detect must leave the main actor free.
    // A main-actor task queued before the call can only run during detect if detect has left the main actor;
    // if detect ran on the main actor, the task would wait until detect returned.
    @MainActor
    @Test("Case 11: detect called from the main actor leaves the main actor free")
    func detectLeavesTheMainActorFree() async throws {
        let detector = try BundledDetector.shared.get()
        let frame = try greyFrame()
        let flags = MainActorFlags()
        let ticker = Task { @MainActor in flags.tickedDuringDetect = !flags.detectFinished }
        _ = try await detector.detect(in: frame)
        flags.detectFinished = true
        await ticker.value
        #expect(flags.tickedDuringDetect)
    }

    @Test("Case 12: the detector keeps no reference to the frame's image after detect")
    func frameImageIsNotKept() async throws {
        let detector = try BundledDetector.shared.get()
        let frame = try greyFrame()
        let before = CFGetRetainCount(frame.image)
        _ = try await detector.detect(in: frame)
        #expect(CFGetRetainCount(frame.image) == before)
    }
}
