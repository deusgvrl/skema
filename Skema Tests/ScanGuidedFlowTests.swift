//
//  ScanGuidedFlowTests.swift
//  Skema Tests
//
//  The guided tap scan (Sketch UT Review T01–T10): Floor → Subject → Camera → Light → Finish, picked
//  automatically; one centred instruction with its small line guides each step. The floor is found by pointing the
//  phone at it, without a tap (A10-112).
//  Camera and screen as in ScanTapTests: (720, 960) is the middle of the picture; depth is a wall `metres` ahead.
//

import CoreGraphics
import Foundation
import MeasureKit
import simd
import Testing
@testable import Skema_Photo

private let screen = CGSize(width: 1440, height: 1920)
private let middle = CGPoint(x: 720, y: 960)
private let leftOfMiddle = CGPoint(x: 720, y: 576)
private let belowMiddle = CGPoint(x: 720, y: 1344)

@MainActor
@Suite("Scan steps")
struct ScanStepTests {
    @Test("Five steps with their lines, in order (copy decided 24 Nov 2026)")
    func titles() {
        #expect(ScanStep.allCases.map(\.title) == [
            "Point at the floor", "Tap the subject", "Tap the camera", "Tap a light", "Tap the next light"
        ])
    }

    @Test("Each step says what is done once it is", arguments: [
        (ScanStep.floor, "Floor found"), (.subject, "Subject set"), (.camera, "Camera added"), (.light, "Light added")
    ])
    func doneTitles(step: ScanStep, expected: String) {
        #expect(step.doneTitle == expected)
    }

    @Test("Each step's small line says why, or what to do first")
    func details() {
        #expect(ScanStep.allCases.map(\.detail) == [
            "Heights are measured from it", "Walk up to it first", "Walk up to it first", "Walk up to it first",
            "Or tap Finish Scan if that's all"
        ])
    }

    @Test("Chips: the steps before the current one are done, the current one is now, the rest are still to do",
          arguments: [
            (ScanStep.floor, [ScanChip.State.now, .todo, .todo, .todo]),
            (.camera, [.done, .done, .now, .todo]),
            (.light, [.done, .done, .done, .now]),
            (.finish, [.done, .done, .done, .done])
          ])
    func chipStates(step: ScanStep, states: [ScanChip.State]) {
        #expect(ScanChip.allCases.map { $0.state(at: step) } == states)
    }

    @Test("Chip titles: Floor, Subject, Camera, and the lights counted once there are any")
    func chipTitles() {
        #expect(ScanChip.allCases.map { $0.title(lights: 0) } == ["Floor", "Subject", "Camera", "Lights"])
        #expect(ScanChip.lights.title(lights: 1) == "1 Light")
        #expect(ScanChip.lights.title(lights: 2) == "2 Lights")
    }

    @Test("The step follows what is still missing, always in the same order", arguments: [
        (false, false, 0, 0, ScanStep.floor),
        (true, false, 0, 0, .subject),
        (true, true, 0, 0, .camera),
        (true, true, 0, 2, .camera),
        (true, true, 1, 0, .light),
        (true, true, 1, 1, .finish),
        (false, true, 1, 1, .floor)
    ])
    func current(hasFloor: Bool, hasSubject: Bool, cameras: Int, lights: Int, expected: ScanStep) {
        let step = ScanStep.current(hasFloor: hasFloor, hasSubject: hasSubject, cameras: cameras, lights: lights)
        #expect(step == expected)
    }

    @Test("What a tap sets in each step: nothing on the floor step; after the lights, taps keep adding lights")
    func tapKinds() {
        #expect(ScanStep.allCases.map(\.tapKind) == [nil, .subject, .camera, .light, .light])
    }
}

@MainActor
@Suite("Scan: guided taps")
struct ScanGuidedFlowTests {
    let arSession = FakeARSession()
    private let floor = [makePlane(worldY: -1, isFloor: true)]

    func makeViewModel() -> ScanViewModel {
        ScanViewModel(
            makeScan: { [arSession] in
                ScanSession(session: arSession, frameInterval: 1.0 / 15.0, supportsLiDAR: { true })
            },
            camera: FakeCameraPermission(status: .authorized),
            storageController: StorageController(inMemory: true))
    }

    /// A tap on a frame that shows the floor (so the floor is found first, as the frame loop would have).
    private func tap(_ viewModel: ScanViewModel, at point: CGPoint = middle, metres: Float? = 2) throws {
        viewModel.tap(atScreen: point, screenSize: screen, in: try measuringFrame(at: 0, metres: metres, planes: floor))
    }

    /// One frame of the scan, `planes` as ARKit found them (the floor by default).
    private func look(_ viewModel: ScanViewModel, at time: Double = 0, planes: [ScanPlane]? = nil) throws {
        viewModel.collect(from: try measuringFrame(at: time, metres: 2, planes: planes ?? floor))
    }

    @Test("Case 1: a new scan starts on the floor step, with its line and small line; no tap sets anything yet")
    func startsOnFloor() throws {
        let viewModel = makeViewModel()

        #expect(viewModel.currentStep == .floor && !viewModel.hasFloor)
        #expect(viewModel.instruction.main == "Point at the floor")
        #expect(viewModel.instruction.detail == "Heights are measured from it")
    }

    @Test("Case 2: a frame with ARKit's floor finds it: step 1 is done, and the next tap sets the subject")
    func floorFound() throws {
        let viewModel = makeViewModel()

        try look(viewModel)

        #expect(viewModel.hasFloor)
        #expect(viewModel.completedStep == .floor)
        #expect(viewModel.currentStep == .subject && viewModel.kind == .subject)
        #expect(!viewModel.canUndo)
    }

    @Test("Case 3: a table is not the floor")
    func tableIsNotTheFloor() throws {
        let viewModel = makeViewModel()

        try look(viewModel, planes: [makePlane(worldY: -0.3, isFloor: false)])

        #expect(!viewModel.hasFloor && viewModel.currentStep == .floor)
    }

    @Test("Case 4: no floor for 5 s shows the tip; finding the floor clears it")
    func floorNotFoundTip() throws {
        let viewModel = makeViewModel()

        for tenth in 0...49 { try look(viewModel, at: Double(tenth) / 10, planes: []) }
        #expect(!viewModel.isFloorMissing)
        try look(viewModel, at: 5, planes: [])
        #expect(viewModel.isFloorMissing)
        #expect(viewModel.instruction.main == "Floor not found yet")

        try look(viewModel, at: 5.2)

        #expect(!viewModel.isFloorMissing && viewModel.hasFloor)
    }

    /// A frame in a dark room with no floor in it, its tracking as given; it goes to the tips and to the floor search,
    /// as the frame loop does.
    private func lookInTheDark(_ viewModel: ScanViewModel, at time: Double, tracking: ScanTracking) throws {
        let lit = try measuringFrame(at: time, metres: 2)
        let frame = ScanFrame(timestamp: time, camera: lit.camera, depth: lit.depth, tracking: tracking,
                              ambientIntensity: 100, planes: [])
        viewModel.updateGuidance(for: frame)
        viewModel.collect(from: frame)
    }

    @Test("Case 4b: in a dark room, More light needed stays up while tracking comes and goes, over the floor tip")
    func darkWinsOverNoFloor() throws {
        let viewModel = makeViewModel()
        var shown: Set<String> = []

        for tenth in 0...80 {
            let time = Double(tenth) / 10
            // As in the dark: tracking drops to limited (too little detail) for 0.6 s of every 1.2 s.
            let tracking: ScanTracking = tenth % 12 < 6 ? .normal : .limited(.insufficientFeatures)
            try lookInTheDark(viewModel, at: time, tracking: tracking)
            if time >= 0.5 { shown.insert(viewModel.instruction.main) }
        }

        #expect(viewModel.isFloorMissing)
        #expect(shown == ["More light needed"])
    }

    @Test("Case 5: a tap before the floor is found sets nothing and says to point at the floor")
    func tapBeforeTheFloor() throws {
        let viewModel = makeViewModel()

        viewModel.tap(atScreen: middle, screenSize: screen, in: try measuringFrame(at: 0, metres: 3, planes: []))

        #expect(viewModel.subject == nil && viewModel.items.isEmpty && !viewModel.canUndo)
        #expect(viewModel.feedback == .pointAtFloorFirst)
        #expect(viewModel.instruction.main == "Point at the floor first")
        #expect(viewModel.currentStep == .floor)
    }

    @Test("Case 6: a lower floor found later is the one heights use")
    func lowerFloorLater() throws {
        let viewModel = makeViewModel()
        try look(viewModel)

        try look(viewModel, at: 0.2, planes: floor + [makePlane(worldY: -1.2, isFloor: true)])

        #expect(viewModel.floorY == -1.2)
    }

    @Test("A subject tap with no LiDAR depth sets nothing and says so")
    func tapNoDepth() throws {
        let viewModel = makeViewModel()

        try tap(viewModel, metres: nil)

        #expect(viewModel.subject == nil)
        #expect(viewModel.feedback == .cannotMeasure)
        #expect(viewModel.currentStep == .subject)
    }

    @Test("Subject, camera, light: each tap is the right kind, then the scan can finish")
    func fullSequence() throws {
        let viewModel = makeViewModel()

        try tap(viewModel, metres: 3)
        #expect(viewModel.subject != nil && viewModel.kind == .camera)

        try tap(viewModel, at: leftOfMiddle)
        #expect(viewModel.items.map(\.kind) == [.camera] && viewModel.kind == .light)

        try tap(viewModel, at: belowMiddle)
        #expect(viewModel.items.map(\.kind) == [.camera, .light])
        #expect(viewModel.currentStep == .finish && viewModel.canFinish)
        #expect(viewModel.kind == .light)
        #expect(viewModel.items.allSatisfy { viewModel.box(for: $0, in: screen) != nil })
    }

    @Test("Items are called Camera, Light 1, Light 2: the same name on the tag, in the instruction and the setup")
    func shortTitles() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, metres: 3)
        try tap(viewModel, at: leftOfMiddle)
        try tap(viewModel, at: belowMiddle)
        // A10-106: the second light is on a wall at 3 m; on the first light's wall it would be "Already tapped".
        try tap(viewModel, at: CGPoint(x: 300, y: 1700), metres: 3)

        #expect(viewModel.items.map(\.name) == ["Camera", "Light 1", "Light 2"])
        #expect(viewModel.draftSetup.nodes.map(\.name) == ["Camera", "Light 1", "Light 2"])
        #expect(viewModel.subjectBox(in: screen) != nil)
    }

    @Test("Nothing to undo before the first tap; undo then changes nothing")
    func undoNothing() {
        let viewModel = makeViewModel()

        viewModel.undoTapped()

        #expect(!viewModel.canUndo)
        #expect(viewModel.currentStep == .floor)
    }

    @Test("Undo after the subject tap clears the subject and asks for it again; the floor stays found")
    func undoSubject() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, metres: 3)

        viewModel.undoTapped()

        #expect(viewModel.subject == nil && viewModel.subjectBox(in: screen) == nil)
        #expect(viewModel.hasFloor)
        #expect(viewModel.currentStep == .subject && viewModel.kind == .subject)
        #expect(!viewModel.canUndo)
    }

    @Test("Undo removes the last light and its equipment; the next light takes its number again")
    func undoLight() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, metres: 3)
        try tap(viewModel, at: leftOfMiddle)
        try tap(viewModel, at: belowMiddle)
        // A10-106: each new light is on a wall of its own (3 m, then 4 m); the first light's box also grows over the
        // 3 m wall while that frame is collected, so the light after Undo goes on a 4 m wall.
        try tap(viewModel, at: CGPoint(x: 300, y: 1700), metres: 3)

        viewModel.undoTapped()

        #expect(viewModel.items.map(\.name) == ["Camera", "Light 1"])
        #expect(viewModel.draftSetup.nodes.map(\.name) == ["Camera", "Light 1"])

        try tap(viewModel, at: CGPoint(x: 300, y: 1700), metres: 4)

        #expect(viewModel.items.last?.name == "Light 2")
    }

    @Test("Case 7: undo steps back one tap at a time; the subject is the last, and the floor stays found")
    func undoAll() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, metres: 3)
        try tap(viewModel, at: leftOfMiddle)
        try tap(viewModel, at: belowMiddle)

        viewModel.undoTapped()
        #expect(viewModel.currentStep == .light)
        viewModel.undoTapped()
        #expect(viewModel.currentStep == .camera)
        viewModel.undoTapped()
        #expect(viewModel.currentStep == .subject)
        viewModel.undoTapped()
        #expect(viewModel.currentStep == .subject && viewModel.hasFloor)
        #expect(viewModel.items.isEmpty && viewModel.draftSetup.nodes.isEmpty && !viewModel.canUndo)
    }

    @Test("An item removed by tapping its tag is skipped by undo")
    func undoSkipsRemovedItem() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, metres: 3)
        try tap(viewModel, at: leftOfMiddle)
        let cameraTag = try #require(viewModel.tagPosition(of: viewModel.items[0].anchor, in: screen))
        try tap(viewModel, at: cameraTag)
        #expect(viewModel.items.isEmpty)

        viewModel.undoTapped()

        #expect(viewModel.subject == nil && viewModel.currentStep == .subject)
    }

    @Test("Undo clears the done flash and the last hint")
    func undoClearsFlash() throws {
        let viewModel = makeViewModel()
        try tap(viewModel)

        viewModel.undoTapped()

        #expect(viewModel.completedStep == nil && viewModel.feedback == nil)
    }

    @Test("Every step keeps its small line all through the scan")
    func smallLinesAlwaysShow() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, metres: 3)

        viewModel.clearCompletedStep()

        #expect(viewModel.instruction.main == "Tap the camera")
        #expect(viewModel.instruction.detail == "Walk up to it first")
    }

    @Test("Clearing the done flash keeps the step moved on")
    func clearDone() throws {
        let viewModel = makeViewModel()
        try look(viewModel)

        viewModel.clearCompletedStep()

        #expect(viewModel.completedStep == nil && viewModel.currentStep == .subject)
    }
}

@Suite("Scan item box")
struct ScanItemBoxTests {
    @Test("Points around a spot 2 m ahead give a box around the middle of the screen; none give no box")
    func box() throws {
        let camera = try measuringFrame(at: 0, metres: 2).camera
        let points = [SIMD3<Float>(-0.1, -0.2, -2), SIMD3(0.1, 0.2, -2), SIMD3(0, 0, -2)]

        let rect = try #require(ScanOverlay.screenBox(of: points, camera: camera, screenSize: screen))

        #expect(rect.contains(middle))
        #expect(rect.width < screen.width && rect.height < screen.height)
        #expect(ScanOverlay.screenBox(of: [], camera: camera, screenSize: screen) == nil)
    }
}
