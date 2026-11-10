//
//  ScanSessionTests.swift
//  Skema Tests
//
//  Created by Muhammad Dzakki Abdullah on 10/11/26.
//

import Foundation
import ARKit
import Testing
@testable import Final_Challenge_App

@Suite("Scan session")
struct ScanSessionTests {
    let fake = FakeARSession()

    func makeScan(supportsLiDAR: Bool = true) -> ScanSession {
        ScanSession(session: fake, frameInterval: 0.1, supportsLiDAR: { supportsLiDAR })
    }

    @Test("It listens to ARKit on its own queue, not the main thread")
    func delegateOnPrivateQueue() throws {
        let scan = makeScan()

        #expect(fake.delegate === scan)
        let queue = try #require(fake.delegateQueue)
        #expect(queue !== DispatchQueue.main)
    }

    @Test("It reports whether the iPhone has LiDAR", arguments: [true, false])
    func reportsLiDARSupport(supported: Bool) {
        #expect(makeScan(supportsLiDAR: supported).isLiDARSupported == supported)
    }

    @Test("Start runs world tracking with LiDAR depth and floor planes")
    func startRunsLiDARConfiguration() throws {
        let scan = makeScan()

        try scan.start()

        #expect(scan.state == .running)
        let run = try #require(fake.runs.first)
        let configuration = try #require(run.configuration as? ARWorldTrackingConfiguration)
        #expect(configuration.frameSemantics.contains(.sceneDepth))
        #expect(configuration.planeDetection == [.horizontal])
        #expect(run.options.contains(.resetTracking))
        #expect(run.options.contains(.removeExistingAnchors))
    }

    @Test("Start without LiDAR throws and never runs ARKit")
    func startWithoutLiDARThrows() {
        let scan = makeScan(supportsLiDAR: false)

        #expect(throws: ScanSessionError.lidarUnsupported) {
            try scan.start()
        }
        #expect(scan.state == .idle)
        #expect(fake.runs.isEmpty)
    }

    @Test("A session cannot start twice")
    func startTwiceThrows() throws {
        let scan = makeScan()
        try scan.start()

        #expect(throws: ScanSessionError.alreadyStarted) {
            try scan.start()
        }
        #expect(fake.runs.count == 1)
    }

    @Test("Stop pauses ARKit, keeps the planes and ends the frames")
    func stopKeepsPlanes() async throws {
        let scan = makeScan()
        let frames = scan.frames()
        try scan.start()
        scan.updatePlanes([makePlane(worldY: -1.2, isFloor: true)])

        scan.stop()

        #expect(scan.state == .stopped)
        #expect(fake.pauseCount == 1)
        #expect(scan.planes.count == 1)
        #expect(await collect(frames).isEmpty)
    }

    @Test("Discard pauses ARKit, forgets the planes and ends the frames")
    func discardForgetsPlanes() async throws {
        let scan = makeScan()
        let frames = scan.frames()
        try scan.start()
        scan.updatePlanes([makePlane(worldY: -1.2, isFloor: true)])

        scan.discard()

        #expect(scan.state == .discarded)
        #expect(fake.pauseCount == 1)
        #expect(scan.planes.isEmpty)
        #expect(await collect(frames).isEmpty)
    }

    @Test("Ending a scan twice does nothing the second time")
    func endTwice() throws {
        let scan = makeScan()
        try scan.start()

        scan.stop()
        scan.discard()

        #expect(scan.state == .stopped)
        #expect(fake.pauseCount == 1)
    }

    @Test("Frames go through only while running, and not faster than the interval")
    func framesThrottledWhileRunning() throws {
        let scan = makeScan()
        #expect(!scan.acceptsFrame(at: 0))

        try scan.start()
        #expect(scan.acceptsFrame(at: 1.0))
        #expect(!scan.acceptsFrame(at: 1.05))
        #expect(scan.acceptsFrame(at: 1.1))

        scan.stop()
        #expect(!scan.acceptsFrame(at: 2.0))
    }

    @Test("Every listener gets each delivered frame")
    func framesReachEveryListener() async throws {
        let scan = makeScan()
        let detector = scan.frames()
        let measurer = scan.frames()
        try scan.start()

        scan.deliver(try makeScanFrame(timestamp: 1.0))
        scan.stop()

        #expect(await collect(detector).map(\.timestamp) == [1.0])
        #expect(await collect(measurer).map(\.timestamp) == [1.0])
    }

    @Test("A denied camera fails the scan and pauses ARKit")
    func cameraDeniedFails() throws {
        let scan = makeScan()
        try scan.start()

        scan.fail(with: ARError(.cameraUnauthorized))

        #expect(scan.state == .failed(.cameraDenied))
        #expect(fake.pauseCount == 1)
    }

    @Test("An interruption holds frames back until it ends")
    func interruption() throws {
        let scan = makeScan()
        try scan.start()

        scan.setInterrupted(true)
        #expect(scan.state == .interrupted)
        #expect(!scan.acceptsFrame(at: 1.0))

        scan.setInterrupted(false)
        #expect(scan.state == .running)
        #expect(scan.acceptsFrame(at: 2.0))
    }

    @Test("Listeners hear each state change, ending with the last one")
    func statesStream() async throws {
        let scan = makeScan()
        let states = scan.states()

        try scan.start()
        scan.setInterrupted(true)
        scan.setInterrupted(false)
        scan.stop()

        #expect(await collect(states) == [.running, .interrupted, .running, .stopped])
    }
}
