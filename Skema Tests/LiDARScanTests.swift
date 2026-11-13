//
//  LiDARScanTests.swift
//  Skema Tests
//
//  The LiDAR-only tap scan (a second scan screen, no object detection): the photographer taps the subject and each
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
@testable import Final_Challenge_App

private let screen = CGSize(width: 1440, height: 1920)
private let middle = CGPoint(x: 720, y: 960)
private let leftOfMiddle = CGPoint(x: 720, y: 576)

@MainActor
@Suite("LiDAR tap scan")
struct LiDARScanTests {
    let arSession = FakeARSession()
    private let floor = [makePlane(worldY: -1, isFloor: true)]

    func makeViewModel(storage: StorageController? = nil) -> LiDARScanViewModel {
        LiDARScanViewModel(
            makeScan: { [arSession] in
                ScanSession(session: arSession, frameInterval: 1.0 / 15.0, supportsLiDAR: { true })
            },
            camera: FakeCameraPermission(status: .authorized),
            storageController: storage ?? StorageController(inMemory: true))
    }

    private func tap(_ viewModel: LiDARScanViewModel, _ kind: LiDARTapKind, at point: CGPoint = middle,
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
        #expect(viewModel.message == "Point the phone at the floor first")
    }

    @Test("A tap on the subject puts it at the LiDAR point under the tap")
    func subjectTap() throws {
        let viewModel = makeViewModel()

        try tap(viewModel, .subject, metres: 3)

        let subject = try #require(viewModel.subject)
        #expect(simd_length(subject - SIMD3(0, 0, -3)) < 0.05)
        #expect(viewModel.message == nil)
    }

    @Test("A tap on a light or camera adds one named item and one draft equipment")
    func itemTap() throws {
        let viewModel = makeViewModel()

        try tap(viewModel, .light)

        #expect(viewModel.items.map(\.name) == ["Studio Lighting 1"])
        #expect(viewModel.draftSetup.nodes.map(\.category) == [.light])
        #expect(viewModel.draftSetup.nodes.map(\.name) == ["Studio Lighting 1"])
    }

    @Test("Items are numbered per kind in tap order")
    func numberedPerKind() throws {
        let viewModel = makeViewModel()

        try tap(viewModel, .light)
        try tap(viewModel, .camera, at: leftOfMiddle)
        try tap(viewModel, .light, at: CGPoint(x: 720, y: 1344))

        #expect(viewModel.items.map(\.name) == ["Studio Lighting 1", "Camera 1", "Studio Lighting 2"])
    }

    @Test("A tap on a spot with no LiDAR depth adds nothing and says so")
    func noDepth() throws {
        let viewModel = makeViewModel()
        viewModel.kind = .light

        viewModel.tap(atScreen: middle, screenSize: screen,
                      in: try measuringFrame(at: 0, metres: nil, planes: floor))

        #expect(viewModel.items.isEmpty)
        #expect(viewModel.message == "No LiDAR depth there")
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

        try tap(viewModel, .light, at: leftOfMiddle)

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
        let light = try #require(viewModel.draftSetup.nodes.first)
        let height = try #require(Double(light.height.replacingOccurrences(of: " m", with: "")))
        #expect(light.distance == "1.00")
        // A light is measured at the middle of its head: here the column from 3 cm above the floor up to the top of
        // the wall at 2 m, so its middle is 1.24 m above the floor.
        #expect(abs(height - 1.24) < 0.05)
        #expect(abs(light.position.x) < 2 && abs(light.position.y - 100) < 2)
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
        #expect(viewModel.statusText(for: item) == "Saved" && viewModel.isSaved(item))
        #expect(light.distance == "1.00" && !light.height.isEmpty)
        #expect(abs(light.position.y - 100) < 2)
        #expect(viewModel.subjectStatusText == "Saved" && viewModel.subjectIsSaved)
    }

    @Test("An item tapped before the subject waits for it, and nothing is written")
    func waitsForTheSubject() throws {
        let viewModel = makeViewModel()

        try tap(viewModel, .light)

        let item = try #require(viewModel.items.first)
        #expect(viewModel.statusText(for: item) == "Waiting for the subject" && !viewModel.isSaved(item))
        #expect(try #require(viewModel.draftSetup.nodes.first).distance.isEmpty)
    }

    @Test("An item only seen farther than 5 m says too far, and so does a subject")
    func tooFar() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, .subject, metres: 6)
        try tap(viewModel, .light, metres: 6)

        let item = try #require(viewModel.items.first)
        #expect(viewModel.statusText(for: item) == "Too far, over 5 m")
        #expect(viewModel.subjectStatusText == "Too far, over 5 m" && !viewModel.subjectIsSaved)
        #expect(try #require(viewModel.draftSetup.nodes.first).distance.isEmpty)
    }

    @Test("A column with too few LiDAR points says so")
    func tooFewPoints() throws {
        let viewModel = makeViewModel()
        // A floor 1.3 m above the phone leaves only a thin strip of the wall inside the column's heights.
        viewModel.kind = .light
        viewModel.tap(atScreen: middle, screenSize: screen,
                      in: try measuringFrame(at: 0, metres: 2, planes: [makePlane(worldY: 1.3, isFloor: true)]))

        let item = try #require(viewModel.items.first)
        #expect(viewModel.statusText(for: item) == "Not enough LiDAR points, tap again")
        #expect(!viewModel.isSaved(item))
    }

    @Test("A measured item next to an unmeasured subject points to the subject's tag")
    func subjectNotMeasured() throws {
        let viewModel = makeViewModel()
        try tap(viewModel, .subject, metres: 6)

        try tap(viewModel, .light, metres: 2)

        let item = try #require(viewModel.items.first)
        #expect(viewModel.statusText(for: item) == "Subject not measured, see its tag")
        #expect(!viewModel.isSaved(item))
    }

    // MARK: Saving the setup (dev's flow)

    @Test("Finish Scan puts the draft setup, with its equipment, into storage")
    func finishInsertsTheSetup() throws {
        let storage = StorageController(inMemory: true)
        let viewModel = makeViewModel(storage: storage)
        try tap(viewModel, .light)

        viewModel.finishTapped()

        let saved = try #require(storage.fetchAllSetups().first)
        #expect(saved.nodes.map(\.name) == ["Studio Lighting 1"])
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
