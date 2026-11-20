//
//  ScanGuidedFlowTests.swift
//  Skema Tests
//
//  The guided tap scan (Sketch UT Review T01–T10): Floor → Subject → Camera → Light → Finish, picked
//  automatically; a step-by-step tutorial on first use, a ? to replay it after.
//  Camera and screen as in ScanTapTests: (720, 960) is the middle of the picture; depth is a wall `metres` ahead.
//

import CoreGraphics
import Foundation
import MeasureKit
import simd
import Testing
@testable import Final_Challenge_App

private let screen = CGSize(width: 1440, height: 1920)
private let middle = CGPoint(x: 720, y: 960)
private let leftOfMiddle = CGPoint(x: 720, y: 576)
private let belowMiddle = CGPoint(x: 720, y: 1344)

@Suite("Scan steps")
struct ScanStepTests {
    @Test("Five steps with the Sketch titles, in order")
    func titles() {
        #expect(ScanStep.allCases.map(\.title) == [
            "Tap the floor", "Tap your product", "Tap the camera", "Tap each light", "Tap Finish Scan"
        ])
        #expect(ScanStep.floor.positionLabel == "STEP 1 OF 5")
        #expect(ScanStep.finish.positionLabel == "STEP 5 OF 5")
    }

    @Test("Each tap step says what is done once it is", arguments: [
        (ScanStep.floor, "Floor set"), (.subject, "Subject set"), (.camera, "Camera added"), (.light, "Light added")
    ])
    func doneTitles(step: ScanStep, expected: String) {
        #expect(step.doneTitle == expected)
    }

    @Test("Messages follow Sketch; the camera and light steps say to walk up to the item")
    func messages() {
        #expect(ScanStep.floor.message == "Point down at the floor and tap it. Heights are measured from it.")
        #expect(ScanStep.subject.message == "Point at the product and tap it. Every distance is measured from it.")
        #expect(ScanStep.camera.message.hasPrefix("Walk up to the camera and tap it."))
        #expect(ScanStep.light.message == "Walk up to a light and tap it. Tap every light in the setup.")
        #expect(ScanStep.finish.message == "Tap any other lights first, then finish.")
    }

    @Test("Without the tutorial, a short hint names the next tap")
    func hints() {
        #expect(ScanStep.floor.hint == "Tap the floor to start")
        #expect(ScanStep.light.hint == "Tap each light")
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

    @Test("What a tap sets in each step; after the lights, taps keep adding lights")
    func tapKinds() {
        #expect(ScanStep.allCases.map(\.tapKind) == [.floor, .subject, .camera, .light, .light])
    }
}

@Suite("Scan floor height")
struct ScanFloorTests {
    @Test("A floor plane close to the tapped point wins; otherwise the tapped point itself")
    func refine() {
        let planes = [HorizontalPlane(y: -1.02, isFloor: true), HorizontalPlane(y: -0.3, isFloor: false)]

        #expect(ScanFloor.height(tappedY: -0.95, planes: planes) == -1.02)
        #expect(ScanFloor.height(tappedY: -0.6, planes: planes) == -0.6)
        #expect(ScanFloor.height(tappedY: -0.95, planes: []) == -0.95)
    }
}

@MainActor
@Suite("Scan: guided taps and tutorial")
struct ScanGuidedFlowTests {
    let arSession = FakeARSession()
    private let floor = [makePlane(worldY: -1, isFloor: true)]

    func makeSettings(done: Bool = false) -> ScanGuideSettings {
        let settings = ScanGuideSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.isTutorialDone = done
        return settings
    }

    func makeViewModel(tutorial: ScanGuideSettings) -> ScanViewModel {
        ScanViewModel(
            makeScan: { [arSession] in
                ScanSession(session: arSession, frameInterval: 1.0 / 15.0, supportsLiDAR: { true })
            },
            camera: FakeCameraPermission(status: .authorized),
            storageController: StorageController(inMemory: true),
            tutorial: tutorial)
    }

    private func tap(_ viewModel: ScanViewModel, at point: CGPoint = middle, metres: Float? = 2) throws {
        viewModel.tap(atScreen: point, screenSize: screen, in: try measuringFrame(at: 0, metres: metres, planes: floor))
    }

    @Test("A new scan starts on the floor step, with the tutorial on first use only")
    func startsOnFloor() {
        let first = makeViewModel(tutorial: makeSettings())
        let later = makeViewModel(tutorial: makeSettings(done: true))

        #expect(first.currentStep == .floor && first.kind == .floor)
        #expect(first.isTutorialVisible)
        #expect(!later.isTutorialVisible)
    }

    @Test("Tapping the floor sets it, shows the step as done and moves on to the subject")
    func floorTap() throws {
        let viewModel = makeViewModel(tutorial: makeSettings())

        try tap(viewModel)

        #expect(viewModel.hasFloor)
        #expect(viewModel.floorAnchor != nil)
        #expect(viewModel.completedStep == .floor)
        #expect(viewModel.currentStep == .subject && viewModel.kind == .subject)
    }

    @Test("A floor tap with no LiDAR depth sets nothing and says so")
    func floorTapNoDepth() throws {
        let viewModel = makeViewModel(tutorial: makeSettings())

        try tap(viewModel, metres: nil)

        #expect(!viewModel.hasFloor)
        #expect(viewModel.message == "No LiDAR depth there")
        #expect(viewModel.currentStep == .floor)
    }

    @Test("Floor, subject, camera, light: each tap is the right kind, then the scan can finish")
    func fullSequence() throws {
        let settings = makeSettings()
        let viewModel = makeViewModel(tutorial: settings)

        try tap(viewModel, metres: 2)
        try tap(viewModel, metres: 3)
        #expect(viewModel.subject != nil && viewModel.kind == .camera)

        try tap(viewModel, at: leftOfMiddle)
        #expect(viewModel.items.map(\.kind) == [.camera] && viewModel.kind == .light)

        try tap(viewModel, at: belowMiddle)
        #expect(viewModel.items.map(\.kind) == [.camera, .light])
        #expect(viewModel.currentStep == .finish && viewModel.canFinish)
        #expect(viewModel.kind == .light)
        #expect(settings.isTutorialDone)
        #expect(viewModel.items.allSatisfy { viewModel.box(for: $0, in: screen) != nil })
    }

    @Test("Tags say Camera and Light, numbered only when there are several; the subject gets a box too")
    func shortTitles() throws {
        let viewModel = makeViewModel(tutorial: makeSettings())
        try tap(viewModel, metres: 2)
        try tap(viewModel, metres: 3)
        try tap(viewModel, at: leftOfMiddle)
        try tap(viewModel, at: belowMiddle)
        try tap(viewModel, at: CGPoint(x: 300, y: 1700))

        #expect(viewModel.items.map(viewModel.shortTitle(for:)) == ["Camera", "Light 1", "Light 2"])
        #expect(viewModel.subjectBox(in: screen) != nil)
    }

    @Test("Skip hides the tutorial for good; ? replays it")
    func skipAndReplay() {
        let settings = makeSettings()
        let viewModel = makeViewModel(tutorial: settings)

        viewModel.skipTutorial()
        #expect(!viewModel.isTutorialVisible && settings.isTutorialDone)

        viewModel.replayTutorial()
        #expect(viewModel.isTutorialVisible)
    }

    @Test("Clearing the done flash keeps the step moved on")
    func clearDone() throws {
        let viewModel = makeViewModel(tutorial: makeSettings())
        try tap(viewModel)

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
