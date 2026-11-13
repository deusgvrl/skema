//
//  ScanSubjectTests.swift
//  Skema Tests
//
//  A10-62 follow-up: the photographer taps the subject. The subject gets a mask (Apple's subject lifting),
//  its points give the subject's base, and Finish Scan writes the measured values onto the draft equipment.
//  Camera: 1920 x 1440 picture, fx = fy = 1000, centre (960, 720), at the origin looking along -z.
//  Depth map: 128 x 96, the same depth everywhere, good confidence.
//

import CoreGraphics
import Foundation
import MeasureKit
import MeasureKitVision
import simd
import Testing
@testable import Final_Challenge_App

private let screen = CGSize(width: 1440, height: 1920)
private let middleOfScreen = CGPoint(x: 720, y: 960)

/// A 640 x 640 mask with 1s in the columns and rows given (of the sideways picture).
private func rectangle(columns: Range<Int>, rows: Range<Int>) -> InstanceMask {
    var pixels = [UInt8](repeating: 0, count: 640 * 640)
    for row in rows { for column in columns { pixels[row * 640 + column] = 1 } }
    return InstanceMask(width: 640, height: 640, pixels: pixels)
}

/// The middle of the picture, where the tap lands.
private let productMask = rectangle(columns: 256..<384, rows: 192..<384)
/// A product on the right of the picture: its base is about 1.15 m to the right of the tap.
private let sideMask = rectangle(columns: 384..<512, rows: 192..<384)
/// Somewhere else in the picture: used to tell one tap's mask from another's.
private let cornerMask = rectangle(columns: 0..<64, rows: 0..<64)

/// Stands in for Apple's subject lifting: answers each call with the next result (the last one repeats),
/// after that call's delay.
final class FakeSubjectSegmenter: SubjectSegmenting, @unchecked Sendable {
    private let lock = NSLock()
    private let results: [InstanceMask?]
    private let delays: [Duration]
    private var calls = 0

    init(_ results: [InstanceMask?] = [nil], delays: [Duration] = []) {
        self.results = results
        self.delays = delays
    }

    func mask(atNative point: CGPoint, in frame: ScanFrame) async -> InstanceMask? {
        let index = lock.withLock {
            defer { calls += 1 }
            return calls
        }
        if index < delays.count { try? await Task.sleep(for: delays[index]) }
        return results[min(index, results.count - 1)]
    }
}

@MainActor
@Suite("Scan view model: the subject")
struct ScanSubjectTests {
    let arSession = FakeARSession()

    final class MadeScans {
        var all: [ScanSession] = []
    }

    func makeViewModel(detector: FakeEquipmentDetector, segmenter: FakeSubjectSegmenter = FakeSubjectSegmenter(),
                       made: MadeScans = MadeScans()) -> ScanViewModel {
        ScanViewModel(
            makeScan: { [arSession] in
                let scan = ScanSession(session: arSession, frameInterval: 1.0 / 15.0, supportsLiDAR: { true })
                made.all.append(scan)
                return scan
            },
            camera: FakeCameraPermission(status: .authorized),
            detector: detector,
            subjectSegmenter: segmenter
        )
    }

    // MARK: Tap on the subject, and the values written at Finish (A10-62 follow-up, A10-21)

    @Test("Tapping the subject puts it where the depth under the tap is, with a Subject ✓ tag")
    func tapSetsTheSubject() async throws {
        let viewModel = makeViewModel(detector: FakeEquipmentDetector())
        await viewModel.detect(in: try measuringFrame(at: 0, metres: 3))

        let done = viewModel.setSubject(atScreen: middleOfScreen, screenSize: screen,
                                        in: try measuringFrame(at: 0, metres: 3))

        let subject = try #require(viewModel.subject)
        #expect(done)
        #expect(simd_length(subject - SIMD3(0, 0, -3)) < 0.05)
        #expect(try #require(viewModel.overlay(in: screen)).subject?.tag == "Subject ✓")
    }

    @Test("A tap on a frame without depth leaves the subject as it was")
    func tapWithoutDepth() async throws {
        let viewModel = makeViewModel(detector: FakeEquipmentDetector())

        let done = viewModel.setSubject(atScreen: middleOfScreen, screenSize: screen,
                                        in: try measuringFrame(at: 0, metres: nil))

        #expect(!done)
        #expect(viewModel.subject == nil)
    }

    @Test("A tap before any frame came in does nothing")
    func tapBeforeAnyFrame() {
        let viewModel = makeViewModel(detector: FakeEquipmentDetector())

        #expect(!viewModel.setSubject(atScreen: middleOfScreen, screenSize: screen))
        #expect(viewModel.subject == nil)
    }

    @Test("A tap uses the newest frame the scan delivered")
    func tapUsesTheLatestDeliveredFrame() async throws {
        let made = MadeScans()
        let viewModel = makeViewModel(detector: FakeEquipmentDetector(), made: made)
        await viewModel.start()
        let scan = try #require(made.all.first)

        scan.deliver(try measuringFrame(at: 0, metres: 3))
        for _ in 0..<50 where !viewModel.setSubject(atScreen: middleOfScreen, screenSize: screen) {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(viewModel.subject != nil)
    }

    @Test("A second tap replaces the subject")
    func secondTapReplacesTheSubject() async throws {
        let viewModel = makeViewModel(detector: FakeEquipmentDetector())
        await viewModel.detect(in: try measuringFrame(at: 0, metres: 3))
        _ = viewModel.setSubject(atScreen: middleOfScreen, screenSize: screen, in: try measuringFrame(at: 0, metres: 3))

        _ = viewModel.setSubject(atScreen: middleOfScreen, screenSize: screen, in: try measuringFrame(at: 0, metres: 2))

        let subject = try #require(viewModel.subject)
        #expect(simd_length(subject - SIMD3(0, 0, -2)) < 0.05)
    }

    /// The subject wall is 3 m ahead, the light patch 2 m ahead, the floor 0.945 m below the phone.
    private func finishedSetup(floor: Bool = true) async throws -> ScanViewModel {
        let viewModel = makeViewModel(detector: FakeEquipmentDetector(finds: [.studioLighting], mask: patchMask))
        _ = viewModel.setSubject(atScreen: middleOfScreen, screenSize: screen, in: try measuringFrame(at: 0, metres: 3))
        let planes = floor ? [makePlane(worldY: -0.945, isFloor: true)] : []
        for tenth in 0...10 {
            await viewModel.detect(in: try measuringFrame(at: Double(tenth) / 10, metres: 2, planes: planes))
        }
        viewModel.finishTapped()
        return viewModel
    }

    @Test("Finish Scan writes each accepted light's distance, height and plan position")
    func finishWritesValues() async throws {
        let viewModel = try await finishedSetup()

        let light = try #require(viewModel.draftSetup.nodes.first)
        #expect(light.distance == "1.00")
        // A light is measured at its middle: the patch is level with the phone, 0.945 m above the floor.
        let height = try #require(Double(light.height))
        #expect(abs(height - 0.945) < 0.04)
        // On the phone's side of the subject, so below it on the plan: 1 m is 100 points.
        #expect(abs(light.position.x) < 2)
        #expect(abs(light.position.y - 100) < 2)
    }

    @Test("Without a floor plane the height stays empty but distance and position are still written")
    func noFloorNoHeight() async throws {
        let viewModel = try await finishedSetup(floor: false)

        let light = try #require(viewModel.draftSetup.nodes.first)
        #expect(light.height.isEmpty)
        #expect(light.distance == "1.00")
    }

    @Test("Without a subject nothing is written")
    func noSubjectNothingWritten() async throws {
        let viewModel = makeViewModel(detector: FakeEquipmentDetector(finds: [.studioLighting], mask: patchMask))
        for tenth in 0...10 {
            await viewModel.detect(in: try measuringFrame(at: Double(tenth) / 10, metres: 2))
        }

        viewModel.finishTapped()

        let light = try #require(viewModel.draftSetup.nodes.first)
        #expect(light.distance.isEmpty && light.height.isEmpty && light.position == .zero)
    }

    // MARK: The subject's mask

    /// The middle of the mask's box across the picture, as a fraction (0...1).
    private func centreX(of mask: InstanceMask?) throws -> Double {
        let box = try #require(mask.flatMap { MaskMapping.bounds(of: $0) })
        return box.x + box.width / 2
    }

    /// A look at `time` so the screen has a camera, then a tap on the middle of the screen.
    private func tapped(_ viewModel: ScanViewModel, at time: Double = 0) async throws {
        await viewModel.detect(in: try measuringFrame(at: time, metres: 3))
        _ = viewModel.setSubject(atScreen: middleOfScreen, screenSize: screen,
                                 in: try measuringFrame(at: time, metres: 3))
        await viewModel.subjectMaskSettled()
    }

    @Test("A mask found under the tap moves the subject to the mask and is drawn in blue")
    func maskFoundForTheSubject() async throws {
        let viewModel = makeViewModel(detector: FakeEquipmentDetector(),
                                      segmenter: FakeSubjectSegmenter([productMask]))

        try await tapped(viewModel)

        let shown = try #require(viewModel.overlay(in: screen)?.subject)
        #expect(abs(try centreX(of: viewModel.subjectMask) - 0.5) < 0.02)
        #expect(shown.mask == viewModel.subjectMask)
        #expect(shown.maskColor == .blue)
        #expect(shown.tag == "Subject ✓")
        let subject = try #require(viewModel.subject)
        #expect(abs(subject.x) < 0.05 && abs(subject.z + 3) < 0.05)
    }

    @Test("No mask under the tap: the subject is the depth patch, with a tag and no mask")
    func noMaskKeepsThePatch() async throws {
        let viewModel = makeViewModel(detector: FakeEquipmentDetector(), segmenter: FakeSubjectSegmenter([nil]))

        try await tapped(viewModel)

        let shown = try #require(viewModel.overlay(in: screen)?.subject)
        #expect(viewModel.subjectMask == nil)
        #expect(shown.mask == nil && shown.maskColor == nil)
        #expect(shown.tag == "Subject ✓")
        #expect(viewModel.subject != nil)
    }

    @Test("The mask stays on the screen for the whole scan")
    func maskStays() async throws {
        let viewModel = makeViewModel(detector: FakeEquipmentDetector(),
                                      segmenter: FakeSubjectSegmenter([productMask]))
        try await tapped(viewModel)

        await viewModel.detect(in: try measuringFrame(at: 10, metres: 3))

        let shown = try #require(viewModel.overlay(in: screen)?.subject)
        #expect(shown.mask != nil && shown.maskColor == .blue)
    }

    @Test("The mask follows the product: 1 m to the right, the product is drawn further left")
    func maskFollowsTheProduct() async throws {
        let viewModel = makeViewModel(detector: FakeEquipmentDetector(),
                                      segmenter: FakeSubjectSegmenter([productMask]))
        try await tapped(viewModel)

        await viewModel.detect(in: try measuringFrame(at: 5, metres: 3, cameraX: 1))

        // The product is 3 m ahead and now 1 m to the camera's left: 1000 * 1 / 3 px left of the middle.
        #expect(abs(try centreX(of: viewModel.subjectMask) - (0.5 - 1000.0 / 3 / 1920)) < 0.02)
    }

    @Test("When the product is out of view, no mask is drawn but the subject is kept")
    func maskLeavesTheScreen() async throws {
        let viewModel = makeViewModel(detector: FakeEquipmentDetector(),
                                      segmenter: FakeSubjectSegmenter([productMask]))
        try await tapped(viewModel)

        await viewModel.detect(in: try measuringFrame(at: 5, metres: 3, cameraX: 20))

        #expect(viewModel.subjectMask == nil)
        #expect(viewModel.subject != nil)
        #expect(viewModel.overlay(in: screen)?.subject?.mask == nil)
    }

    @Test("When two taps overlap, the last tap's mask wins even if the first answer arrives later")
    func lastTapWins() async throws {
        let viewModel = makeViewModel(
            detector: FakeEquipmentDetector(),
            segmenter: FakeSubjectSegmenter([cornerMask, productMask], delays: [.milliseconds(150)]))
        await viewModel.detect(in: try measuringFrame(at: 0, metres: 3))

        _ = viewModel.setSubject(atScreen: middleOfScreen, screenSize: screen,
                                 in: try measuringFrame(at: 0, metres: 3))
        _ = viewModel.setSubject(atScreen: middleOfScreen, screenSize: screen,
                                 in: try measuringFrame(at: 0, metres: 3))
        await viewModel.subjectMaskSettled()
        try await Task.sleep(for: .milliseconds(300))

        #expect(abs(try centreX(of: viewModel.subjectMask) - 0.5) < 0.02)
    }

    @Test("The subject's base comes from its mask, not from the small patch under the tap")
    func baseFromTheMask() async throws {
        let viewModel = makeViewModel(detector: FakeEquipmentDetector(finds: [.studioLighting], mask: patchMask),
                                      segmenter: FakeSubjectSegmenter([sideMask]))
        try await tapped(viewModel)
        // `tapped` already made a look at 0 s (with the wall 3 m ahead). The light is first seen 2 m ahead at 0.1 s,
        // so it is accepted at 1.1 s.
        for tenth in 1...12 {
            await viewModel.detect(in: try measuringFrame(at: Double(tenth) / 10, metres: 2))
        }

        viewModel.finishTapped()

        // The light is 1 m ahead of the subject's wall and 1.15 m to the left of its base: sqrt(1.15^2 + 1^2).
        let light = try #require(viewModel.draftSetup.nodes.first)
        let metres = try #require(Double(light.distance.replacingOccurrences(of: " m", with: "")))
        #expect(abs(metres - 1.52) < 0.03)
    }

    // MARK: Subject lifting helpers (the Vision call itself is checked on a device)

    @Test("A tap on the native picture becomes a tap on the oriented picture", arguments: [
        (ImageOrientation.up, CGPoint(x: 0.2, y: 0.7), CGPoint(x: 0.2, y: 0.7)),
        (ImageOrientation.right, CGPoint(x: 0.2, y: 0.7), CGPoint(x: 0.3, y: 0.2)),
        (ImageOrientation.left, CGPoint(x: 0.2, y: 0.7), CGPoint(x: 0.7, y: 0.8)),
        (ImageOrientation.down, CGPoint(x: 0.2, y: 0.7), CGPoint(x: 0.8, y: 0.3))
    ])
    func orientedTap(orientation: ImageOrientation, native: CGPoint, expected: CGPoint) {
        let point = SubjectSegmenter.orientedPoint(fromNative: native, orientation: orientation)
        #expect(abs(point.x - expected.x) < 1e-9 && abs(point.y - expected.y) < 1e-9)
    }

    @Test("The instance under the tap becomes a mask, and the other instances and the background do not")
    func instanceUnderTheTap() throws {
        // 4 x 2 labels: background, instance 1 (two columns), instance 2.
        let labels: [UInt8] = [0, 1, 1, 2, 0, 1, 1, 2]

        let mask = try #require(SubjectSegmenter.mask(fromLabels: labels, width: 4, height: 2,
                                                       tap: CGPoint(x: 0.4, y: 0.25), orientation: .up))

        #expect(mask == InstanceMask(width: 4, height: 2, pixels: [0, 1, 1, 0, 0, 1, 1, 0]))
    }

    @Test("A tap on the background gives no mask")
    func tapOnTheBackground() {
        let labels: [UInt8] = [0, 1, 1, 2, 0, 1, 1, 2]
        #expect(SubjectSegmenter.mask(fromLabels: labels, width: 4, height: 2,
                                      tap: CGPoint(x: 0.1, y: 0.5), orientation: .up) == nil)
    }

    @Test("The mask is turned into the native picture, like the detector's masks")
    func maskIsTurnedToNative() throws {
        // 2 wide x 3 high oriented labels; instance 1 is the top-right pixel. Right: native is 3 wide x 2 high,
        // and oriented (ox, oy) lands on native (oy, W - 1 - ox) = (0, 0).
        let labels: [UInt8] = [0, 1, 0, 0, 0, 0]

        let mask = try #require(SubjectSegmenter.mask(fromLabels: labels, width: 2, height: 3,
                                                       tap: CGPoint(x: 0.9, y: 0.1), orientation: .right))

        #expect(mask == InstanceMask(width: 3, height: 2, pixels: [1, 0, 0, 0, 0, 0]))
    }
}
