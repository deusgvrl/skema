//
//  ScanGrownBoxTests.swift
//  Skema Tests
//
//  A10-106: a tapped light is measured from its grown box (cases 8, 12, 13, 15, 16; Amadeus, 20 Nov).
//  Camera and screen as in ScanTapTests: the screen is the upright picture at scale 1, so a screen point (x, y) is the
//  picture pixel (u = y, v = 1440 - x). Depth is a flat wall 2 m ahead, which the paint takes as one surface. Every
//  frame shows ARKit's floor 1 m below the phone, so the floor is found without a tap (A10-112).
//

import CoreGraphics
import Foundation
import MeasureKit
import simd
import Testing
@testable import Skema_Photo

private let screen = CGSize(width: 1440, height: 1920)
/// World (0, 0, -2) on the wall.
private let middle = CGPoint(x: 720, y: 960)
/// World (-0.768, 0, -2): where the camera is tapped.
private let cameraSpot = CGPoint(x: 720, y: 576)
/// World (0.768, 0, -2): where the first light is tapped.
private let lightSpot = CGPoint(x: 720, y: 1344)

@MainActor
@Suite("A10-106 grown box in the scan")
struct ScanGrownBoxTests {
    let arSession = FakeARSession()
    private let planes = [makePlane(worldY: -1, isFloor: true)]

    private func makeViewModel() -> ScanViewModel {
        ScanViewModel(
            makeScan: { [arSession] in
                ScanSession(session: arSession, frameInterval: 1.0 / 15.0, supportsLiDAR: { true })
            },
            camera: FakeCameraPermission(status: .authorized),
            storageController: StorageController(inMemory: true))
    }

    private func tap(_ viewModel: ScanViewModel, at point: CGPoint, at time: Double = 0) throws {
        viewModel.tap(atScreen: point, screenSize: screen, in: try measuringFrame(at: time, metres: 2, planes: planes))
    }

    /// Subject and camera tapped (the floor is found from the frames): the next tap adds a light.
    private func scanWithCamera() throws -> ScanViewModel {
        let viewModel = makeViewModel()
        try tap(viewModel, at: middle)
        try tap(viewModel, at: cameraSpot)
        return viewModel
    }

    private func width(of box: MeasureKit.WorldBox?) -> Float? {
        box.map { $0.max.x - $0.min.x }
    }

    @Test("Case 8: the light's first small box comes from the frame of its tap, and it grows over the wall")
    func firstBoxFromTheTapFrame() throws {
        let viewModel = try scanWithCamera()

        try tap(viewModel, at: lightSpot, at: 5)

        let light = try #require(viewModel.items.first { $0.kind == .light })
        // The 10 cm column would be 20 cm wide; the paint takes the whole 3.84 m wide wall.
        #expect(try #require(width(of: viewModel.itemBounds[light.id])) > 1)
    }

    @Test("Case 16: a camera keeps the 10 cm column")
    func cameraKeepsTheColumn() throws {
        let viewModel = try scanWithCamera()

        let camera = try #require(viewModel.items.first { $0.kind == .camera })
        #expect(try #require(width(of: viewModel.itemBounds[camera.id])) <= 0.2 + 1e-4)
    }

    @Test("Case 12: a light tap inside Light 1's big box makes no new item and says Light 1 already added")
    func secondTapOnTheSameLight() throws {
        let viewModel = try scanWithCamera()
        try tap(viewModel, at: lightSpot)

        // 356 points from Light 1's tag, so it is not a tap on the tag; world x = 1.48 m, inside the wall's box.
        try tap(viewModel, at: CGPoint(x: 720, y: 1700))

        #expect(viewModel.items.map(\.name) == ["Camera 1", "Studio Lighting 1"])
        #expect(viewModel.draftSetup.nodes.count == 2)
        #expect(viewModel.feedback == .alreadyAdded(light: 1))
        #expect(viewModel.instruction.main == "Light 1 already added")
    }

    @Test("Case 13: a light tap inside a camera's box makes a new light")
    func lightTapInsideACameraBox() throws {
        let viewModel = try scanWithCamera()

        // 120 points from the camera's tag; world (-0.768, -0.24, -2), inside the camera's column.
        try tap(viewModel, at: CGPoint(x: 600, y: 576))

        #expect(viewModel.items.map(\.name) == ["Camera 1", "Studio Lighting 1"])
    }

    @Test("Case 15: after Undo removes Light 1, a tap on the same place makes a new light")
    func tapAgainAfterUndo() throws {
        let viewModel = try scanWithCamera()
        try tap(viewModel, at: lightSpot)

        viewModel.undoTapped()
        try tap(viewModel, at: lightSpot)

        #expect(viewModel.items.map(\.name) == ["Camera 1", "Studio Lighting 1"])
        #expect(viewModel.feedback == nil)
    }
}
