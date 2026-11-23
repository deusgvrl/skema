//
//  ScanTapTests.swift
//  Skema Tests
//
//  The scan's taps (LiDAR only, no object detection): the photographer taps the subject and each
//  light or camera, each tap paints a column of LiDAR points (A10-41 painted items, nothing is drawn),
//  Finish writes the plan values.
//  Camera: 1920 x 1440 picture, fx = fy = 1000, centre (960, 720), at the origin looking along -z.
//  Screen 1440 x 1920: (720, 960) is the middle of the picture, (720, 576) is picture (0.3, 0.5).
//  Depth map 128 x 96, the same depth everywhere. The floor plane is 1 m below the phone.
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

@MainActor
@Suite("Scan: taps, live results and Finish")
struct ScanTapTests {
    let arSession = FakeARSession()
    private let floor = [makePlane(worldY: -1, isFloor: true)]

    func makeViewModel(storage: StorageController? = nil) -> ScanViewModel {
        ScanViewModel(
            makeScan: { [arSession] in
                ScanSession(session: arSession, frameInterval: 1.0 / 15.0, supportsLiDAR: { true })
            },
            camera: FakeCameraPermission(status: .authorized),
            storageController: storage ?? StorageController(inMemory: true))
    }

    private func tap(_ viewModel: ScanViewModel, _ kind: ScanTapKind, at point: CGPoint = middle,
                     metres: Float = 2, withFloor: Bool = true) throws {
        viewModel.kind = kind
        viewModel.tap(atScreen: point, screenSize: screen,
                      in: try measuringFrame(at: 0, metres: metres, planes: withFloor ? floor : []))
    }

    // MARK: Taps

    @Test("Without a floor plane a tap does nothing and says why")
    func noFloorNoTap() throws {
        let viewModel = makeViewModel()

        try tap(viewModel, .subject, metres: 3, withFloor: false)

        #expect(viewModel.subject == nil)
        #expect(viewModel.feedback == .pointAtFloorFirst)
    }

    @Test("A tap on the subject puts it at the LiDAR point under the tap")
    func subjectTap() throws {
        let viewModel = makeViewModel()

        try tap(viewModel, .subject, metres: 3)

        let subject = try #require(viewModel.subject)
        #expect(simd_length(subject - SIMD3(0, 0, -3)) < 0.05)
        #expect(viewModel.feedback == nil)
    }

    @Test("A tap on a light or camera adds one named item and one draft equipment")
    func itemTap() throws {
        let viewModel = makeViewModel()

        try tap(viewModel, .light)

        #expect(viewModel.items.map(\.name) == ["Light 1"])
        #expect(viewModel.draftSetup.nodes.map(\.category) == [.light])
        #expect(viewModel.draftSetup.nodes.map(\.name) == ["Light 1"])
    }

    @Test("Items are numbered per kind in tap order")
    func numberedPerKind() throws {
        let viewModel = makeViewModel()

        try tap(viewModel, .light)
        try tap(viewModel, .camera, at: leftOfMiddle)
        // A10-106: the second light is on a wall at 3 m, another surface than the first light's wall at 2 m.
        try tap(viewModel, .light, at: CGPoint(x: 720, y: 1344), metres: 3)

        #expect(viewModel.items.map(\.name) == ["Light 1", "Camera", "Light 2"])
    }

    @Test("A tap on a spot with no LiDAR depth adds nothing and says so")
    func noDepth() throws {
        let viewModel = makeViewModel()
        viewModel.kind = .light

        viewModel.tap(atScreen: middle, screenSize: screen,
                      in: try measuringFrame(at: 0, metres: nil, planes: floor))

        #expect(viewModel.items.isEmpty)
        #expect(viewModel.feedback == .cannotMeasure)
    }

    @Test("Tapping an item's tag spot again removes it and its equipment")
    func tapAgainRemoves() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, .light)

        try tap(viewModel, .light)

        #expect(viewModel.items.isEmpty)
        #expect(viewModel.draftSetup.nodes.isEmpty)
    }

    @Test("A tap far from every item adds a new item instead of removing one")
    func farTapAdds() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, .light)

        // A10-106: on the same flat wall the second tap would be "Already tapped"; a wall at 3 m is another surface.
        try tap(viewModel, .light, at: leftOfMiddle, metres: 3)

        #expect(viewModel.items.count == 2)
    }

    // MARK: Live results

    @Test("Once there is a subject, each item shows its live distance and height")
    func liveResult() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, .subject, metres: 3)
        try tap(viewModel, .light, metres: 2)

        viewModel.collect(from: try measuringFrame(at: 1, metres: 2, planes: floor))

        let result = try #require(viewModel.items.first?.result)
        #expect(result.status == .measured)
        #expect(abs(try #require(result.distanceToSubject) - 1) < 0.02)
    }

    // MARK: Finish and the plan

    @Test("Finish needs a subject, a camera and a light")
    func finishRule() throws {
        let viewModel = makeViewModel()
        #expect(!viewModel.canFinish)

        try tap(viewModel, .subject, metres: 3)
        try tap(viewModel, .light, metres: 2)
        #expect(!viewModel.canFinish)

        try tap(viewModel, .camera, at: leftOfMiddle, metres: 2)
        #expect(viewModel.canFinish)
    }

    @Test("Finish writes the light's distance, height and plan position")
    func finishWritesTheValues() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, .subject, metres: 3)
        try tap(viewModel, .light, metres: 2)

        viewModel.finishTapped()

        // The subject wall is 3 m ahead, the light's wall 2 m ahead: 1 m apart, on the phone's side (plan down).
        // A10-106: the distance goes to the back of the light's grown box, 1 cm nearer the phone (the 2 cm minimum
        // depth of a flat wall's box): 1.01 m.
        let light = try #require(viewModel.draftSetup.nodes.first)
        let height = try #require(Double(light.height.replacingOccurrences(of: " m", with: "")))
        #expect(light.distance == "1.01")
        // A10-106: a light is measured at the middle height of its grown box: here the wall painted from 3 cm above
        // the floor up to the top of the picture at 2 m, so its middle is 1.24 m above the floor.
        #expect(abs(height - 1.24) < 0.05)
        #expect(abs(light.position.x) < 2 && abs(light.position.y - 100) < 2)
    }

    @Test("Finish writes the subject's height above the floor onto the setup")
    func finishWritesTheSubjectHeight() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, .subject, metres: 3)

        viewModel.finishTapped()

        // The subject is a wall 3 m ahead; its column reaches as high as the picture shows it, well above the floor.
        let height = try #require(Double(viewModel.draftSetup.subjectHeight))
        #expect(height > 0.5 && height < 3)
    }

    @Test("An item seen only farther than 5 m keeps empty values")
    func outOfRangeItemStaysEmpty() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, .subject, metres: 3)
        try tap(viewModel, .light, metres: 6)

        viewModel.finishTapped()

        let light = try #require(viewModel.draftSetup.nodes.first)
        #expect(light.distance.isEmpty && light.height.isEmpty && light.position == .zero)
    }

    @Test("Without a subject nothing is written")
    func noSubjectNothingWritten() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, .light)

        viewModel.finishTapped()

        let light = try #require(viewModel.draftSetup.nodes.first)
        #expect(light.distance.isEmpty && light.height.isEmpty && light.position == .zero)
    }

    // MARK: Saved

    @Test("As soon as an item is measured its values are on the equipment and its tag says Saved")
    func savedAtOnce() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, .subject, metres: 3)

        try tap(viewModel, .light, metres: 2)

        let item = try #require(viewModel.items.first)
        let light = try #require(viewModel.draftSetup.nodes.first)
        #expect(viewModel.isSaved(item))
        // A10-106: the distance goes to the back of the light's grown box. A flat wall's box gets the 2 cm minimum
        // depth, so its back is 1 cm nearer the phone: 1.01 m.
        #expect(light.distance == "1.01" && !light.height.isEmpty)
        #expect(abs(light.position.y - 100) < 2)
        #expect(viewModel.subjectIsSaved)
    }

    @Test("An item tapped before the subject waits for it, and nothing is written")
    func waitsForTheSubject() throws {
        let viewModel = makeViewModel()

        try tap(viewModel, .light)

        let item = try #require(viewModel.items.first)
        #expect(!viewModel.isSaved(item))
        #expect(try #require(viewModel.draftSetup.nodes.first).distance.isEmpty)
    }

    @Test("An item only seen farther than 5 m is out of range, and so is a subject")
    func tooFar() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, .subject, metres: 6)
        try tap(viewModel, .light, metres: 6)

        let item = try #require(viewModel.items.first)
        #expect(item.result?.status == .outOfRange && !viewModel.isSaved(item))
        #expect(viewModel.subjectResult?.status == .outOfRange && !viewModel.subjectIsSaved)
        #expect(try #require(viewModel.draftSetup.nodes.first).distance.isEmpty)
    }

    @Test("An item with too few LiDAR points is not saved")
    func tooFewPoints() throws {
        let viewModel = makeViewModel()
        // A floor 1.3 m above the phone leaves only a thin strip of the wall inside the column's heights.
        viewModel.kind = .light
        viewModel.tap(atScreen: middle, screenSize: screen,
                      in: try measuringFrame(at: 0, metres: 2, planes: [makePlane(worldY: 1.3, isFloor: true)]))

        let item = try #require(viewModel.items.first)
        #expect(item.result?.status == .tooFewPoints && !viewModel.isSaved(item))
    }

    @Test("A measured item next to an unmeasured subject is not saved")
    func subjectNotMeasured() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, .subject, metres: 6)

        try tap(viewModel, .light, metres: 2)

        let item = try #require(viewModel.items.first)
        #expect(item.result?.status == .measured && !viewModel.isSaved(item))
    }

    // MARK: "Too far" and "Need a closer look" in the instruction

    private func look(_ viewModel: ScanViewModel, at time: Double, metres: Float,
                      planes: [ScanPlane]? = nil) throws {
        viewModel.collect(from: try measuringFrame(at: time, metres: metres, planes: planes ?? floor))
    }

    @Test("1.5 s after a light tap that is still too far, the instruction says so; not before")
    func tooFarMessage() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, .subject, metres: 3)
        try tap(viewModel, .light, metres: 6)

        try look(viewModel, at: 1.4, metres: 6)
        #expect(viewModel.feedback == nil)
        try look(viewModel, at: 1.6, metres: 6)

        #expect(viewModel.feedback == .tooFar)
        #expect(viewModel.instruction.main == "Too far to measure")
    }

    @Test("1.5 s after a light tap with too few points, the instruction asks for a closer look")
    func closerLookMessage() throws {
        let viewModel = makeViewModel()
        let highFloor = [makePlane(worldY: 1.3, isFloor: true)]
        viewModel.kind = .light
        viewModel.tap(atScreen: middle, screenSize: screen,
                      in: try measuringFrame(at: 0, metres: 2, planes: highFloor))

        try look(viewModel, at: 1.6, metres: 2, planes: highFloor)

        #expect(viewModel.feedback == .needsCloserLook)
    }

    @Test("A light that is measured shows no message 1.5 s later")
    func measuredNoMessage() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, .subject, metres: 3)
        try tap(viewModel, .light, metres: 2)

        try look(viewModel, at: 1.6, metres: 2)

        #expect(viewModel.feedback == nil)
    }

    @Test("A subject that is too far gets the message too")
    func subjectTooFarMessage() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, .subject, metres: 6)

        try look(viewModel, at: 1.6, metres: 6)

        #expect(viewModel.feedback == .tooFar)
    }

    @Test("Undo before the 1.5 s drops the check")
    func undoDropsTheCheck() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, .subject, metres: 3)
        try tap(viewModel, .light, metres: 6)

        viewModel.undoTapped()
        try look(viewModel, at: 1.6, metres: 6)

        #expect(viewModel.feedback == nil)
    }

    // MARK: Saving the setup (dev's flow)

    @Test("Finish Scan puts the draft setup, with its equipment, into storage")
    func finishInsertsTheSetup() throws {
        let storage = StorageController(inMemory: true)
        let viewModel = makeViewModel(storage: storage)
        try tap(viewModel, .light)

        viewModel.finishTapped()

        let saved = try #require(storage.fetchAllSetups().first)
        #expect(saved.nodes.map(\.name) == ["Light 1"])
    }

    @Test("Closing the scan removes the draft setup from storage")
    func closeDeletesTheSetup() throws {
        let storage = StorageController(inMemory: true)
        let viewModel = makeViewModel(storage: storage)
        try tap(viewModel, .light)
        viewModel.finishTapped()

        viewModel.closeTapped()

        #expect(storage.fetchAllSetups().isEmpty)
    }
}

extension ScanTapTests {
    @Test("Finish Scan before the scan can finish sets nothing and says what to add first")
    func finishTooEarly() throws {
        let viewModel = makeViewModel()
        #expect(!viewModel.tryFinish())
        #expect(viewModel.feedback == .pointAtFloorFirst)

        try tap(viewModel, .subject, metres: 3)
        try tap(viewModel, .light, metres: 2)
        #expect(!viewModel.tryFinish())
        #expect(viewModel.feedback == .addFirst(.camera))
        #expect(viewModel.instruction.main == "Add the camera first")

        try tap(viewModel, .camera, at: leftOfMiddle, metres: 2)
        #expect(viewModel.tryFinish())
    }
}
