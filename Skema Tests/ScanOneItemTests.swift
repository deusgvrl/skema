//
//  ScanOneItemTests.swift
//  Skema Tests
//
//  Scan screen phase 3 (decided 24 Nov 2026): one item at a time. After a tap, the item is being scanned until the
//  phone has seen it from two spots at least 45° apart (and it is measured); only then does the next step show, and
//  until then a tap that would set something new sets nothing (the hard gate). Undo is the way out.
//  Camera and screen as in ScanTapTests: a flat wall `metres` ahead, ARKit's floor 1 m below the phone.
//

import CoreGraphics
import Foundation
import MeasureKit
import simd
import Testing
@testable import Skema_Photo

private let screen = CGSize(width: 1440, height: 1920)
/// World (0, 0, -d) on a wall d metres ahead.
private let middle = CGPoint(x: 720, y: 960)
/// World (-0.384 d, 0, -d): the camera.
private let leftOfMiddle = CGPoint(x: 720, y: 576)
/// World (0.384 d, 0, -d): the first light.
private let belowMiddle = CGPoint(x: 720, y: 1344)

@MainActor
@Suite("Scan: one item at a time")
struct ScanOneItemTests {
    let arSession = FakeARSession()
    private let floor = [makePlane(worldY: -1, isFloor: true)]

    private func makeViewModel() -> ScanViewModel {
        ScanViewModel(
            makeScan: { [arSession] in
                ScanSession(session: arSession, frameInterval: 1.0 / 15.0, supportsLiDAR: { true })
            },
            camera: FakeCameraPermission(status: .authorized),
            storageController: StorageController(inMemory: true))
    }

    private func frame(metres: Float, cameraX: Float = 0) throws -> ScanFrame {
        try measuringFrame(at: 0, metres: metres, planes: floor, cameraX: cameraX)
    }

    private func tap(_ viewModel: ScanViewModel, at point: CGPoint = middle, metres: Float = 2) throws {
        viewModel.tap(atScreen: point, screenSize: screen, in: try frame(metres: metres))
    }

    /// Looks at the scene from where the photographer stands (`cameraX`), `times` frames.
    private func stand(_ viewModel: ScanViewModel, metres: Float = 2, cameraX: Float = 0, times: Int = 10) throws {
        for _ in 0..<times { viewModel.collect(from: try frame(metres: metres, cameraX: cameraX)) }
    }

    /// Walks around `anchor`: half its distance to the left, then to the right (about 53° around it).
    private func walk(_ viewModel: ScanViewModel, around anchor: SIMD3<Float>?, metres: Float = 2) throws {
        let anchor = try #require(anchor)
        for side: Float in [-1, 1] {
            viewModel.collect(from: try frame(metres: metres, cameraX: anchor.x + side * metres / 2))
        }
    }

    /// The subject (3 m) and the camera, each walked around: the next tap adds a light.
    private func readyForLights() throws -> ScanViewModel {
        let viewModel = makeViewModel()
        try tap(viewModel, metres: 3)
        try walk(viewModel, around: viewModel.subject, metres: 3)
        try tap(viewModel, at: leftOfMiddle)
        try walk(viewModel, around: viewModel.items.last?.anchor)
        return viewModel
    }

    @Test("A light seen from one spot is never done: it keeps asking to walk around it, and the step stays on lights")
    func oneSpotIsNotDone() throws {
        let viewModel = try readyForLights()
        try tap(viewModel, at: belowMiddle)

        try stand(viewModel)

        let light = try #require(viewModel.items.last)
        #expect(!viewModel.isDone(light))
        #expect(viewModel.instruction.main == "Walk around Light 1")
        #expect(viewModel.instruction.detail == "Keep it in view until its tag turns green")
        #expect(viewModel.currentStep == .light && !viewModel.canFinish)
    }

    @Test("Walking 45° around the light makes it done: Light 1 done, then the next step")
    func walkingMakesItDone() throws {
        let viewModel = try readyForLights()
        try tap(viewModel, at: belowMiddle)
        #expect(viewModel.justDone == nil)

        try walk(viewModel, around: viewModel.items.last?.anchor)

        let light = try #require(viewModel.items.last)
        #expect(viewModel.isDone(light))
        #expect(viewModel.justDone == .item("Light 1"))
        #expect(viewModel.instruction.main == "Light 1 done")
        #expect(viewModel.currentStep == .finish && viewModel.canFinish)
        viewModel.clearDone()
        #expect(viewModel.instruction.main == "Tap the next light")
    }

    @Test("The subject and the camera need the walk too; each says it is done")
    func subjectAndCamera() throws {
        let viewModel = makeViewModel()
        try stand(viewModel, times: 1)
        viewModel.clearDone()
        try tap(viewModel, metres: 3)
        #expect(viewModel.currentStep == .subject)
        #expect(viewModel.instruction.main == "Walk around the subject")

        try walk(viewModel, around: viewModel.subject, metres: 3)
        #expect(viewModel.subjectIsDone && viewModel.justDone == .subject)
        #expect(viewModel.currentStep == .camera)

        try tap(viewModel, at: leftOfMiddle)
        #expect(viewModel.justDone == nil)
        #expect(viewModel.instruction.main == "Walk around the camera")
        try walk(viewModel, around: viewModel.items.last?.anchor)
        #expect(viewModel.justDone == .item("Camera") && viewModel.currentStep == .light)
    }

    @Test("Hard gate: a tap on the next item while one is being scanned sets nothing and says which to finish")
    func gateBlocksTheNextTap() throws {
        let viewModel = try readyForLights()
        try tap(viewModel, at: belowMiddle)

        // A second light on a wall of its own (3 m), so it is not "already added".
        try tap(viewModel, at: CGPoint(x: 300, y: 1700), metres: 3)

        #expect(viewModel.items.map(\.name) == ["Camera", "Light 1"])
        #expect(viewModel.feedback == .finishFirst("Light 1"))
        #expect(viewModel.instruction.main == "Finish Light 1 first")
    }

    @Test("Hard gate on the subject: tapping the camera before the subject is done sets nothing")
    func gateOnTheSubject() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, metres: 3)

        try tap(viewModel, at: leftOfMiddle)

        #expect(viewModel.items.isEmpty)
        #expect(viewModel.feedback == .finishFirst("the subject"))
    }

    @Test("Finish Scan while a light is being scanned says to finish it first")
    func gateOnFinish() throws {
        let viewModel = try readyForLights()
        try tap(viewModel, at: belowMiddle)

        #expect(!viewModel.tryFinish())
        #expect(viewModel.feedback == .finishFirst("Light 1"))
    }

    @Test("Undo takes back the light being scanned and frees the next tap")
    func undoFreesTheGate() throws {
        let viewModel = try readyForLights()
        try tap(viewModel, at: belowMiddle)

        viewModel.undoTapped()
        try tap(viewModel, at: CGPoint(x: 300, y: 1700), metres: 3)

        #expect(viewModel.items.map(\.name) == ["Camera", "Light 1"])
        #expect(viewModel.feedback == nil)
    }

    @Test("While the light is only seen beyond 5 m, it asks to walk closer to it")
    func tooFarLine() throws {
        let viewModel = try readyForLights()
        try tap(viewModel, metres: 6)

        try stand(viewModel, metres: 6)

        #expect(viewModel.items.last?.result?.status == .outOfRange)
        #expect(viewModel.instruction.main == "Walk closer to Light 1")
        #expect(viewModel.instruction.detail == "It's more than 5 m away")
    }

    @Test("The ring fills: half for enough points, half for the walk")
    func progress() throws {
        let viewModel = try readyForLights()
        try tap(viewModel, at: belowMiddle)
        let light = try #require(viewModel.items.last)
        let standing = viewModel.progress(of: light)

        try walk(viewModel, around: light.anchor)

        #expect(standing >= 0.5 && standing < 0.6)
        #expect(viewModel.progress(of: try #require(viewModel.items.last)) == 1)
    }

    @Test("Finding the floor says Floor found")
    func floorFound() throws {
        let viewModel = makeViewModel()

        try stand(viewModel, times: 1)

        #expect(viewModel.justDone == .floor)
        #expect(viewModel.instruction.main == "Floor found")
    }
}
