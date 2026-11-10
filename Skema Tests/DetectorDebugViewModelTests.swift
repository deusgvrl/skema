//
//  DetectorDebugViewModelTests.swift
//  Skema Tests
//
//  The Debug-only detector test screen (A10-60 device testing). Only the ViewModel is tested (Amadeus, 10 Nov).
//

import CoreGraphics
import Foundation
import MeasureKit
import Testing
@testable import Final_Challenge_App

/// A detector double: returns queued results in order and records how many calls overlap.
private actor FakeDetector: EquipmentDetecting {
    private var results: [Result<[EquipmentDetection], Error>]
    private var running = 0
    private(set) var maxRunning = 0
    private(set) var calls = 0

    init(_ results: [Result<[EquipmentDetection], Error>]) { self.results = results }

    func detect(in frame: ScanFrame) async throws -> [EquipmentDetection] {
        calls += 1
        running += 1
        maxRunning = max(maxRunning, running)
        try await Task.sleep(for: .milliseconds(20))
        running -= 1
        return try results.isEmpty ? [] : results.removeFirst().get()
    }
}

private struct Boom: Error {}

private func detection(_ kind: EquipmentKind, _ confidence: Float) -> EquipmentDetection {
    EquipmentDetection(kind: kind, confidence: confidence, mask: InstanceMask(width: 1, height: 1, pixels: [1]))
}

private func frames(_ count: Int) throws -> AsyncStream<ScanFrame> {
    let all = try (0..<count).map { try makeScanFrame(timestamp: TimeInterval($0)) }
    return AsyncStream { continuation in
        all.forEach { continuation.yield($0) }
        continuation.finish()
    }
}

/// A clock that returns the given times in order.
@MainActor private final class FakeClock {
    private var times: [TimeInterval]
    init(_ times: [TimeInterval]) { self.times = times }
    func now() -> TimeInterval { times.isEmpty ? 0 : times.removeFirst() }
}

@MainActor
@Suite("Detector debug screen")
struct DetectorDebugViewModelTests {
    private func model(_ detector: FakeDetector, clock: FakeClock? = nil,
                       thermal: ProcessInfo.ThermalState = .nominal) -> DetectorDebugViewModel {
        let clock = clock ?? FakeClock([])
        return DetectorDebugViewModel(detector: detector, now: { clock.now() }, thermalState: { thermal },
                               render: { _, _ in nil })
    }

    @Test("Captions show the label and the confidence in percent, best first")
    func captionsShowLabelAndPercent() async throws {
        let viewModel = model(FakeDetector([.success([detection(.camera, 0.454), detection(.studioLighting, 0.62)])]))
        await viewModel.run(frames: try frames(1))
        #expect(viewModel.captions == ["studio lighting 62%", "Camera 45%"])
    }

    @Test("ms per detection is the time detect took")
    func millisecondsPerDetection() async throws {
        let viewModel = model(FakeDetector([.success([])]), clock: FakeClock([10.0, 10.08]))
        await viewModel.run(frames: try frames(1))
        #expect(abs((viewModel.lastMilliseconds ?? 0) - 80) < 0.001)
    }

    @Test("Only one detection runs at a time")
    func oneDetectionAtATime() async throws {
        let detector = FakeDetector([])
        await model(detector).run(frames: try frames(3))
        #expect(await detector.calls == 3)
        #expect(await detector.maxRunning == 1)
    }

    @Test("A failed detection shows a message, and the next frame still runs")
    func failureShowsMessageAndContinues() async throws {
        let detector = FakeDetector([.failure(Boom()), .success([detection(.camera, 0.5)])])
        let viewModel = model(detector)
        await viewModel.run(frames: try frames(1))
        #expect(viewModel.errorText != nil)
        await viewModel.run(frames: try frames(1))
        #expect(viewModel.errorText == nil)
        #expect(viewModel.captions == ["Camera 50%"])
    }

    @Test("The phone's heat state is shown as a word")
    func thermalStateText() async throws {
        let viewModel = model(FakeDetector([]), thermal: .serious)
        await viewModel.run(frames: try frames(1))
        #expect(viewModel.thermalText == "serious")
    }
}

@Suite("Detections per second")
struct DetectionRateTests {
    @Test("Counts detections that finished in the last second only")
    func countsTheLastSecond() {
        var rate = DetectionRate()
        for time in [0.1, 0.5, 1.05, 1.2] { rate.record(at: time) }
        #expect(rate.count(at: 1.2) == 3)   // 0.5, 1.05 and 1.2; 0.1 is more than 1 s old
        #expect(rate.count(at: 2.6) == 0)
    }
}
