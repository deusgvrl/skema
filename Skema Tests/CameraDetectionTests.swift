//
//  CameraDetectionTests.swift
//  Skema Tests
//
//  A10-90 cases D3–D8 (written in the A10-90 Jira issue): cameras from Apple Vision at 60%,
//  and one detector that runs YOLOE (studio lighting) and Vision (cameras) at the same time.
//  D1–D2 are in EquipmentDetectorTests. D9 (Vision at every look) is covered by V4 in ScanDetectionTests.
//

import Foundation
import MeasureKit
import MeasureKitVision
import Testing
@testable import Final_Challenge_App

/// A 4 wide, 2 high mask (Vision's oriented frame) with only its top-left pixel on.
private let orientedCorner = InstanceMask(width: 4, height: 2, pixels: [1, 0, 0, 0, 0, 0, 0, 0])
private let lightMask = InstanceMask(width: 1, height: 1, pixels: [1])

private struct SideFailed: Error {}

/// Records how many detectors run at the same moment.
private final class OverlapProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var running = 0
    private var most = 0
    var mostAtOnce: Int { lock.withLock { most } }
    func begin() { lock.withLock { running += 1; most = max(most, running) } }
    func end() { lock.withLock { running -= 1 } }
}

/// Stands in for one side (YOLOE or Vision): returns or throws what the test sets, after a short wait.
private struct SideDetector: EquipmentDetecting {
    let result: Result<[EquipmentDetection], SideFailed>
    var probe: OverlapProbe?
    var delay: Duration = .zero

    func detect(in frame: ScanFrame) async throws -> [EquipmentDetection] {
        probe?.begin()
        defer { probe?.end() }
        if delay > .zero { try? await Task.sleep(for: delay) }
        return try result.get()
    }
}

private let light = EquipmentDetection(kind: .studioLighting, confidence: 0.9, mask: lightMask)
private let camera = EquipmentDetection(kind: .camera, confidence: 0.7, mask: lightMask)

@Suite("Camera detection with Vision, and both detectors together")
struct CameraDetectionTests {
    // MARK: D3–D5: Vision cameras

    @Test("Case D3: a \"camera\" at 60% or more gives a camera with its mask, turned like YOLOE's")
    func cameraAtSixtyIsKept() throws {
        let found = try #require(CameraDetector.camera(from: orientedCorner,
                                                       classifications: [("camera", 0.60)], orientation: .right))
        #expect(found.kind == .camera)
        #expect(found.confidence == 0.60)
        #expect(found.mask == MaskMapping.nativeMask(orientedCorner, orientation: .right))
        // Turned: the oriented 4 x 2 mask is 2 x 4 in the native picture, its corner at column 0, row 3.
        #expect(found.mask.width == 2 && found.mask.height == 4)
        #expect(found.mask.pixels[3 * 2 + 0] == 1)
    }

    @Test("Case D4: a \"camera\" at only 59% is dropped")
    func cameraAtFiftyNineIsDropped() {
        #expect(CameraDetector.camera(from: orientedCorner, classifications: [("camera", 0.59)],
                                      orientation: .right) == nil)
    }

    @Test("Case D5: tripod, lamp or spotlight with camera under 60% is dropped")
    func otherLabelsAreDropped() {
        let classifications: [(identifier: String, confidence: Float)] = [
            ("tripod", 0.8), ("lamp", 0.7), ("spotlight", 0.9), ("camera", 0.3)
        ]
        #expect(CameraDetector.camera(from: orientedCorner, classifications: classifications,
                                      orientation: .right) == nil)
    }

    @Test("Case D5: a camera at 65% is kept even when tripod scores higher")
    func cameraKeptUnderAHigherTripod() throws {
        let found = try #require(CameraDetector.camera(from: orientedCorner,
                                                       classifications: [("tripod", 0.8), ("camera", 0.65)],
                                                       orientation: .right))
        #expect(found.kind == .camera)
        #expect(found.confidence == 0.65)
    }

    // MARK: D6–D8: both together

    @Test("Case D6: a light from YOLOE and a camera from Vision both come back, lights first")
    func bothComeBackLightsFirst() async throws {
        let both = CombinedDetector(lights: SideDetector(result: .success([light])),
                                    cameras: SideDetector(result: .success([camera])))

        let found = try await both.detect(in: try makeScanFrame(timestamp: 0))

        #expect(found.map(\.kind) == [.studioLighting, .camera])
    }

    @Test("Case D6: YOLOE and Vision run at the same time")
    func bothRunAtTheSameTime() async throws {
        let probe = OverlapProbe()
        let both = CombinedDetector(
            lights: SideDetector(result: .success([light]), probe: probe, delay: .milliseconds(50)),
            cameras: SideDetector(result: .success([camera]), probe: probe, delay: .milliseconds(50)))

        _ = try await both.detect(in: try makeScanFrame(timestamp: 0))

        #expect(probe.mostAtOnce == 2)
    }

    @Test("Case D7: when Vision fails, the lights still come through")
    func visionFailsLightsStay() async throws {
        let both = CombinedDetector(lights: SideDetector(result: .success([light])),
                                    cameras: SideDetector(result: .failure(SideFailed())))

        let found = try await both.detect(in: try makeScanFrame(timestamp: 0))

        #expect(found.map(\.kind) == [.studioLighting])
    }

    @Test("Case D7: when YOLOE fails, the cameras still come through")
    func yoloeFailsCamerasStay() async throws {
        let both = CombinedDetector(lights: SideDetector(result: .failure(SideFailed())),
                                    cameras: SideDetector(result: .success([camera])))

        let found = try await both.detect(in: try makeScanFrame(timestamp: 0))

        #expect(found.map(\.kind) == [.camera])
    }

    @Test("Case D8: when both fail, the look fails, so it counts as nothing seen")
    func bothFailTheLookFails() async throws {
        let both = CombinedDetector(lights: SideDetector(result: .failure(SideFailed())),
                                    cameras: SideDetector(result: .failure(SideFailed())))
        let frame = try makeScanFrame(timestamp: 0)

        await #expect(throws: (any Error).self) {
            try await both.detect(in: frame)
        }
    }
}
