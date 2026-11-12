//
//  ScanDetectionTests.swift
//  Skema Tests
//
//  A10-62 cases V1–V9 (written in the A10-62 Jira issue): the scan screen feeds each frame through
//  the detector → 3D sightings → tracking → overlay.
//  Camera: 1920 x 1440 picture, fx = fy = 1000, centre (960, 720), at the origin looking along -z.
//  Depth map: 8 x 6, the same depth everywhere, good confidence. Masks cover the whole picture.
//

import CoreGraphics
import Foundation
import MeasureKit
import simd
import Testing
@testable import Final_Challenge_App

private let screen = CGSize(width: 1440, height: 1920)
private let fullMask = InstanceMask(width: 640, height: 640, pixels: [UInt8](repeating: 1, count: 640 * 640))

private let detectionCamera: CameraModel = {
    var intrinsics = matrix_identity_float3x3
    intrinsics[0][0] = 1000
    intrinsics[1][1] = 1000
    intrinsics[2][0] = 960
    intrinsics[2][1] = 720
    return CameraModel(intrinsics: intrinsics, imageResolution: SIMD2(1920, 1440),
                       cameraToWorld: matrix_identity_float4x4)
}()

/// A frame at `time` seconds. `metres` nil means the frame has no depth.
private func frame(at time: Double, metres: Float? = 2) throws -> ScanFrame {
    let base = try makeScanFrame(timestamp: time)
    return ScanFrame(timestamp: time, image: base.image, orientation: .right, camera: detectionCamera,
                     depth: metres.map { makeDepth(width: 8, height: 6, depth: $0) },
                     tracking: .normal, ambientIntensity: nil, planes: [])
}

private struct DetectorFailed: Error {}

/// Stands in for the YOLOE detector: returns what the test sets, and records each call.
final class FakeEquipmentDetector: EquipmentDetecting, @unchecked Sendable {
    private let lock = NSLock()
    private var found: [EquipmentDetection]
    private var failsNext = false
    private var calls: [Double] = []
    private var running = 0
    private var mostAtOnce = 0
    private let delay: Duration?

    init(finds kinds: [EquipmentKind] = [], delay: Duration? = nil) {
        self.found = kinds.map { EquipmentDetection(kind: $0, confidence: 0.6, mask: fullMask) }
        self.delay = delay
    }

    /// The frame times the detector was asked to look at.
    var callTimes: [Double] { lock.withLock { calls } }
    /// The most detections that were running at the same time.
    var maxAtOnce: Int { lock.withLock { mostAtOnce } }

    func failNextLook() { lock.withLock { failsNext = true } }

    func detect(in frame: ScanFrame) async throws -> [EquipmentDetection] {
        lock.withLock {
            calls.append(frame.timestamp)
            running += 1
            mostAtOnce = max(mostAtOnce, running)
        }
        defer { lock.withLock { running -= 1 } }
        if let delay { try? await Task.sleep(for: delay) }
        return try lock.withLock {
            if failsNext {
                failsNext = false
                throw DetectorFailed()
            }
            return found
        }
    }
}

@MainActor
@Suite("Scan view model: detection and overlay")
struct ScanDetectionTests {
    let arSession = FakeARSession()

    final class MadeScans {
        var all: [ScanSession] = []
    }

    func makeViewModel(detector: FakeEquipmentDetector, made: MadeScans = MadeScans()) -> ScanViewModel {
        ScanViewModel(
            makeScan: { [arSession] in
                let scan = ScanSession(session: arSession, frameInterval: 1.0 / 15.0, supportsLiDAR: { true })
                made.all.append(scan)
                return scan
            },
            camera: FakeCameraPermission(status: .authorized),
            detector: detector
        )
    }

    /// One look every 0.1 s from `start` through `end` seconds.
    func look(_ viewModel: ScanViewModel, from start: Int = 0, through end: Int) async throws {
        for tenth in start...end {
            await viewModel.detect(in: try frame(at: Double(tenth) / 10))
        }
    }

    // MARK: V1–V3

    @Test("Case V1: a camera found once shows Detecting…, an empty ring and a white mask")
    func cameraFoundOnce() async throws {
        let viewModel = makeViewModel(detector: FakeEquipmentDetector(finds: [.camera]))

        await viewModel.detect(in: try frame(at: 0))

        let shown = try #require(viewModel.overlay(in: screen)).items
        #expect(shown.map(\.tag) == ["Detecting…"])
        #expect(shown.map(\.ring) == [0])
        #expect(shown.map(\.maskColor) == [.white])
    }

    @Test("Case V2: the same camera found at every look for 1.0 s becomes Camera 1 ✓ with a green mask")
    func cameraAcceptedAfterOneSecond() async throws {
        let viewModel = makeViewModel(detector: FakeEquipmentDetector(finds: [.camera]))

        try await look(viewModel, through: 10)

        let shown = try #require(viewModel.overlay(in: screen)).items
        #expect(shown.map(\.tag) == ["Camera 1 ✓"])
        #expect(shown.map(\.maskColor) == [.green])
    }

    @Test("Case V3: a frame without depth adds no item")
    func noDepthAddsNothing() async throws {
        let viewModel = makeViewModel(detector: FakeEquipmentDetector(finds: [.camera]))

        await viewModel.detect(in: try frame(at: 0, metres: nil))

        #expect(viewModel.overlay(in: screen)?.items.isEmpty ?? true)
    }

    @Test("Case V3: a frame without depth keeps an accepted item")
    func noDepthKeepsAccepted() async throws {
        let viewModel = makeViewModel(detector: FakeEquipmentDetector(finds: [.camera]))
        try await look(viewModel, through: 10)

        await viewModel.detect(in: try frame(at: 1.1, metres: nil))

        #expect(try #require(viewModel.overlay(in: screen)).items.map(\.tag) == ["Camera 1 ✓"])
    }

    // MARK: V4

    @Test("Case V4: frames at 15 per second are detected at most every 0.1 s")
    func detectsAtTenPerSecond() async throws {
        let detector = FakeEquipmentDetector(finds: [.camera])
        let viewModel = makeViewModel(detector: detector)

        for time in [0, 0.05, 0.1, 0.15, 0.2] {
            await viewModel.detect(in: try frame(at: time))
        }

        #expect(detector.callTimes == [0, 0.1, 0.2])
    }

    @Test("Case V4: a slow detector never runs twice at once, and the LiDAR points still come in")
    func neverTwoAtOnce() async throws {
        let detector = FakeEquipmentDetector(finds: [.camera], delay: .milliseconds(30))
        let made = MadeScans()
        let viewModel = makeViewModel(detector: detector, made: made)
        await viewModel.start()
        let scan = try #require(made.all.first)

        for tenth in 0...5 {
            scan.deliver(try frame(at: Double(tenth) / 10))
            try await Task.sleep(for: .milliseconds(5))
        }
        for _ in 0..<50 where detector.callTimes.count < 2 || viewModel.pointCloud.pointCount == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(detector.callTimes.count >= 1)
        #expect(detector.maxAtOnce == 1)
        #expect(viewModel.pointCloud.pointCount > 0)
    }

    @Test("Case V4: two frames handed over at the same moment give one detection, not two at once")
    func twoAtTheSameMoment() async throws {
        let detector = FakeEquipmentDetector(finds: [.camera], delay: .milliseconds(30))
        let viewModel = makeViewModel(detector: detector)
        let first = try frame(at: 0)
        let second = try frame(at: 0.5)

        async let one: Void = viewModel.detect(in: first)
        async let two: Void = viewModel.detect(in: second)
        _ = await (one, two)

        #expect(detector.maxAtOnce == 1)
        #expect(detector.callTimes.count == 1)
    }

    // MARK: V5

    @Test("Case V5: a failed look keeps the item, pauses its clock, and the next look works")
    func failedLookPausesTheClock() async throws {
        let detector = FakeEquipmentDetector(finds: [.camera])
        let viewModel = makeViewModel(detector: detector)
        await viewModel.detect(in: try frame(at: 0))

        detector.failNextLook()
        await viewModel.detect(in: try frame(at: 0.1))
        let afterFail = try #require(viewModel.overlay(in: screen)).items
        #expect(afterFail.map(\.tag) == ["Detecting…"])
        #expect(afterFail.map(\.ring) == [0])

        await viewModel.detect(in: try frame(at: 0.2))
        let next = try #require(viewModel.overlay(in: screen)).items
        #expect(detector.callTimes == [0, 0.1, 0.2])
        #expect(next.map(\.maskColor) == [.white])
        let ring = try #require(next.first?.ring)
        #expect(abs(ring - 0.1) < 1e-6)
    }

    // MARK: V6

    @Test("Case V6: after Finish Scan or Close, detection stops", arguments: [true, false])
    func finishOrCloseStopsDetection(finish: Bool) async throws {
        let detector = FakeEquipmentDetector(finds: [.camera])
        let made = MadeScans()
        let viewModel = makeViewModel(detector: detector, made: made)
        await viewModel.start()

        if finish { viewModel.finishTapped() } else { viewModel.closeTapped() }
        let scan = try #require(made.all.first)
        scan.deliver(try frame(at: 0))
        for _ in 0..<20 { await Task.yield() }

        #expect(detector.callTimes.isEmpty)
        #expect(viewModel.overlay(in: screen) == nil)
    }

    @Test("Case V6: a detection still running when Finish Scan is tapped changes nothing")
    func finishDuringDetection() async throws {
        let detector = FakeEquipmentDetector(finds: [.camera], delay: .milliseconds(100))
        let made = MadeScans()
        let viewModel = makeViewModel(detector: detector, made: made)
        await viewModel.start()
        let scan = try #require(made.all.first)

        scan.deliver(try frame(at: 0))
        for _ in 0..<50 where detector.callTimes.isEmpty {
            try await Task.sleep(for: .milliseconds(2))
        }
        viewModel.finishTapped()
        try await Task.sleep(for: .milliseconds(200))

        #expect(detector.callTimes == [0])
        #expect(viewModel.overlay(in: screen) == nil)
    }

    // MARK: V7, V9

    @Test("Case V7: with a subject, an accepted camera and an accepted light, Finish Scan is enabled")
    func finishEnabled() async throws {
        let viewModel = makeViewModel(detector: FakeEquipmentDetector(finds: [.camera, .studioLighting]))
        viewModel.subject = SIMD3(0, 0, -1)
        #expect(!viewModel.canFinish)

        try await look(viewModel, through: 10)

        #expect(viewModel.canFinish)
    }

    @Test("Case V9: with no subject chosen, Finish Scan stays disabled")
    func noSubjectNoFinish() async throws {
        let viewModel = makeViewModel(detector: FakeEquipmentDetector(finds: [.camera, .studioLighting]))

        try await look(viewModel, through: 10)

        #expect(viewModel.overlay(in: screen)?.chips == ["Camera • 1", "Studio Lighting • 1"])
        #expect(!viewModel.canFinish)
    }

    // MARK: V8

    @Test("Case V8: an accepted camera is added to the draft setup once")
    func acceptedCameraAddedOnce() async throws {
        let viewModel = makeViewModel(detector: FakeEquipmentDetector(finds: [.camera]))

        try await look(viewModel, through: 9)
        #expect(viewModel.draftSetup.nodes.isEmpty)
        try await look(viewModel, from: 10, through: 60)

        #expect(viewModel.draftSetup.nodes.count == 1)
        let camera = try #require(viewModel.draftSetup.nodes.first)
        #expect(camera.category == .camera)
        #expect(camera.name == "Camera 1")
        #expect(camera.position == .zero)
        #expect(camera.label.isEmpty)
    }

    @Test("Case V8: an accepted light is added as Studio Lighting 1")
    func acceptedLightAdded() async throws {
        let viewModel = makeViewModel(detector: FakeEquipmentDetector(finds: [.studioLighting]))

        try await look(viewModel, through: 10)

        #expect(viewModel.draftSetup.nodes.map(\.category) == [.light])
        #expect(viewModel.draftSetup.nodes.map(\.name) == ["Studio Lighting 1"])
    }
}
