//
//  ScanViewModelTests.swift
//  Skema Tests
//
//  Created by Muhammad Dzakki Abdullah on 10/11/26.
//

import ARKit
import Foundation
import Testing
@testable import Final_Challenge_App

/// Camera permission that tests set up, and that counts how often the system prompt would show.
final class FakeCameraPermission: CameraPermission {
    var status: CameraPermissionStatus
    /// What the user answers when the prompt shows.
    var allowsWhenAsked: Bool
    private(set) var requestCount = 0

    init(status: CameraPermissionStatus, allowsWhenAsked: Bool = true) {
        self.status = status
        self.allowsWhenAsked = allowsWhenAsked
    }

    func request() async -> Bool {
        requestCount += 1
        status = allowsWhenAsked ? .authorized : .denied
        return allowsWhenAsked
    }
}

@MainActor
@Suite("Scan view model: permission and LiDAR")
struct ScanViewModelTests {
    let arSession = FakeARSession()

    /// Every scan the view model makes, so tests can look at them.
    final class MadeScans {
        var all: [ScanSession] = []
    }

    func makeViewModel(
        supportsLiDAR: Bool = true,
        camera: FakeCameraPermission,
        made: MadeScans = MadeScans()
    ) -> ScanViewModel {
        ScanViewModel(
            makeScan: { [arSession] in
                let scan = ScanSession(session: arSession, frameInterval: 0.1, supportsLiDAR: { supportsLiDAR })
                made.all.append(scan)
                return scan
            },
            camera: camera,
            detector: FakeEquipmentDetector()
        )
    }

    @Test("Starts on the starting screen")
    func startsOnStarting() {
        let viewModel = makeViewModel(camera: FakeCameraPermission(status: .authorized))

        #expect(viewModel.screen == .starting)
    }

    @Test("Starts with an empty draft setup for the equipment found")
    func draftStartsEmpty() {
        let viewModel = makeViewModel(camera: FakeCameraPermission(status: .authorized))

        #expect(viewModel.draftSetup.nodes.isEmpty)
    }

    @Test("An iPhone without LiDAR shows the message and never asks for the camera")
    func noLiDAR() async {
        let camera = FakeCameraPermission(status: .notDetermined)
        let viewModel = makeViewModel(supportsLiDAR: false, camera: camera)

        await viewModel.start()

        #expect(viewModel.screen == .lidarUnsupported)
        #expect(camera.requestCount == 0)
        #expect(arSession.runs.isEmpty)
    }

    @Test("With the camera allowed, the scan starts")
    func authorizedStarts() async {
        let viewModel = makeViewModel(camera: FakeCameraPermission(status: .authorized))

        await viewModel.start()

        #expect(viewModel.screen == .scanning)
        #expect(arSession.runs.count == 1)
    }

    @Test("The first time, it asks for the camera, then starts when allowed")
    func asksThenStarts() async {
        let camera = FakeCameraPermission(status: .notDetermined, allowsWhenAsked: true)
        let viewModel = makeViewModel(camera: camera)

        await viewModel.start()

        #expect(camera.requestCount == 1)
        #expect(viewModel.screen == .scanning)
        #expect(arSession.runs.count == 1)
    }

    @Test("Saying no to the prompt shows Camera Access Is Off")
    func askedAndDenied() async {
        let camera = FakeCameraPermission(status: .notDetermined, allowsWhenAsked: false)
        let viewModel = makeViewModel(camera: camera)

        await viewModel.start()

        #expect(camera.requestCount == 1)
        #expect(viewModel.screen == .cameraDenied)
        #expect(arSession.runs.isEmpty)
    }

    @Test("Camera already off shows the message without asking again")
    func alreadyDenied() async {
        let camera = FakeCameraPermission(status: .denied)
        let viewModel = makeViewModel(camera: camera)

        await viewModel.start()

        #expect(camera.requestCount == 0)
        #expect(viewModel.screen == .cameraDenied)
        #expect(arSession.runs.isEmpty)
    }

    @Test("Starting twice runs ARKit once")
    func startTwice() async {
        let viewModel = makeViewModel(camera: FakeCameraPermission(status: .authorized))

        await viewModel.start()
        await viewModel.start()

        #expect(arSession.runs.count == 1)
    }

    @Test("Turning the camera on in Settings starts a new scan on return")
    func returnFromSettings() async {
        let camera = FakeCameraPermission(status: .denied)
        let made = MadeScans()
        let viewModel = makeViewModel(camera: camera, made: made)
        await viewModel.start()

        camera.status = .authorized
        await viewModel.appBecameActive()

        #expect(viewModel.screen == .scanning)
        #expect(arSession.runs.count == 1)
        #expect(made.all.count == 2)
    }

    @Test("Coming back without turning the camera on keeps the message")
    func returnStillDenied() async {
        let camera = FakeCameraPermission(status: .denied)
        let viewModel = makeViewModel(camera: camera)
        await viewModel.start()

        await viewModel.appBecameActive()

        #expect(viewModel.screen == .cameraDenied)
        #expect(arSession.runs.isEmpty)
    }

    @Test("Coming back while scanning changes nothing")
    func returnWhileScanning() async {
        let viewModel = makeViewModel(camera: FakeCameraPermission(status: .authorized))
        await viewModel.start()

        await viewModel.appBecameActive()

        #expect(viewModel.screen == .scanning)
        #expect(arSession.runs.count == 1)
    }

    @Test("ARKit reporting the camera as denied shows Camera Access Is Off")
    func arkitCameraDenied() async throws {
        let made = MadeScans()
        let viewModel = makeViewModel(camera: FakeCameraPermission(status: .authorized), made: made)
        await viewModel.start()

        let scan = try #require(made.all.first)
        scan.fail(with: ARError(.cameraUnauthorized))
        for _ in 0..<100 where viewModel.screen != .cameraDenied {
            await Task.yield()
        }

        #expect(viewModel.screen == .cameraDenied)
    }

    @Test("Each session state shows the right screen", arguments: [
        (ScanSessionState.failed(.cameraDenied), ScanScreen.cameraDenied),
        (.failed(.lidarUnsupported), .lidarUnsupported),
        (.failed(.sessionFailed("Sensor failed")), .failed("Sensor failed"))
    ])
    func mapsStates(state: ScanSessionState, expected: ScanScreen) {
        let viewModel = makeViewModel(camera: FakeCameraPermission(status: .authorized))

        viewModel.handle(state)

        #expect(viewModel.screen == expected)
    }

    @Test("Close stops the camera and discards the scan")
    func closeDiscards() async throws {
        let made = MadeScans()
        let viewModel = makeViewModel(camera: FakeCameraPermission(status: .authorized), made: made)
        await viewModel.start()

        viewModel.closeTapped()

        let scan = try #require(made.all.first)
        #expect(scan.state == .discarded)
        #expect(arSession.pauseCount == 1)
    }

    @Test("Finish stops the camera and keeps the scan")
    func finishStops() async throws {
        let made = MadeScans()
        let viewModel = makeViewModel(camera: FakeCameraPermission(status: .authorized), made: made)
        await viewModel.start()

        viewModel.finishTapped()
        viewModel.closeTapped()

        let scan = try #require(made.all.first)
        #expect(scan.state == .stopped)
        #expect(arSession.pauseCount == 1)
    }

    @Test("While scanning, LiDAR frames build up the room points")
        func scanningCollectsPoints() async throws {
            let made = MadeScans()
            let viewModel = makeViewModel(camera: FakeCameraPermission(status: .authorized), made: made)
            await viewModel.start()

            let scan = try #require(made.all.first)
            scan.deliver(try makeDepthScanFrame(timestamp: 1))
            for _ in 0..<100 where viewModel.pointCloud.pointCount == 0 {
                await Task.yield()
            }

            #expect(viewModel.pointCloud.pointCount == 4)
        }

        @Test("After Finish Scan, no more points are added")
        func finishStopsPoints() async throws {
            let made = MadeScans()
            let viewModel = makeViewModel(camera: FakeCameraPermission(status: .authorized), made: made)
            await viewModel.start()

            viewModel.finishTapped()
            let scan = try #require(made.all.first)
            scan.deliver(try makeDepthScanFrame(timestamp: 1))
            for _ in 0..<20 {
                await Task.yield()
            }

            #expect(viewModel.pointCloud.pointCount == 0)
        }

    @Test("A tracking problem that lasts shows its tip, and recovering hides it")
        func guidanceFromFrames() throws {
            let viewModel = makeViewModel(camera: FakeCameraPermission(status: .authorized))

            viewModel.updateGuidance(for: try makeTrackingFrame(timestamp: 1, tracking: .limited(.excessiveMotion)))
            viewModel.updateGuidance(for: try makeTrackingFrame(timestamp: 1.5, tracking: .limited(.excessiveMotion)))
            let shown = viewModel.guidance
            viewModel.updateGuidance(for: try makeTrackingFrame(timestamp: 2, tracking: .normal))
            viewModel.updateGuidance(for: try makeTrackingFrame(timestamp: 2.5, tracking: .normal))

            #expect(shown == .moveSlower)
            #expect(viewModel.guidance == nil)
        }

        @Test("Finish Scan clears the tip")
        func finishClearsGuidance() async throws {
            let viewModel = makeViewModel(camera: FakeCameraPermission(status: .authorized))
            await viewModel.start()
            viewModel.updateGuidance(for: try makeTrackingFrame(timestamp: 1, tracking: .limited(.excessiveMotion)))
            viewModel.updateGuidance(for: try makeTrackingFrame(timestamp: 1.5, tracking: .limited(.excessiveMotion)))

            viewModel.finishTapped()

            #expect(viewModel.guidance == nil)
        }


    @Test("Close before the scan started does nothing")
    func closeBeforeStart() {
        let viewModel = makeViewModel(camera: FakeCameraPermission(status: .denied))

        viewModel.closeTapped()

        #expect(arSession.pauseCount == 0)
    }

    @Test("The symbols on the scan screens exist", arguments: ["video.slash", "iphone.slash"])
    func symbolsExist(name: String) {
        #expect(UIImage(systemName: name) != nil)
    }
}

func makeDepthScanFrame(timestamp: TimeInterval) throws -> ScanFrame {
    let frame = try makeScanFrame(timestamp: timestamp)
    return ScanFrame(
        timestamp: frame.timestamp,
        image: frame.image,
        orientation: frame.orientation,
        camera: makeCamera(size: 8, focal: 8),
        depth: makeDepth(width: 8, height: 8, depth: 1),
        tracking: frame.tracking,
        ambientIntensity: frame.ambientIntensity,
        planes: frame.planes
    )
}

func makeTrackingFrame(timestamp: TimeInterval, tracking: ScanTracking) throws -> ScanFrame {
    let frame = try makeScanFrame(timestamp: timestamp)
    return ScanFrame(
        timestamp: timestamp,
        image: frame.image,
        orientation: frame.orientation,
        camera: frame.camera,
        depth: makeDepth(width: 8, height: 8, depth: 1),
        tracking: tracking,
        ambientIntensity: 1000,
        planes: []
    )
}
