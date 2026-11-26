//
//  ScanPlaneDetectionTests.swift
//  Skema Tests
//
//  Created by Amadeus Gavriel on 26/11/26.
//
//  A10-121 (step 2): ARKit stops looking for planes 1 second after the floor is found. Frames come from
//  `measuringFrame`, and every one that shows the floor has the same floor plane 1 m below the phone.
//

import ARKit
import Foundation
import Testing
@testable import Skema_Photo

@MainActor
@Suite("A10-121 plane search stops after the floor")
struct ScanPlaneDetectionTests {
    let arSession = FakeARSession()
    private let floor = [makePlane(worldY: -1, isFloor: true)]

    /// A view model that is scanning on a fake ARKit session. The first run is the start.
    private func makeScanningViewModel() async -> ScanViewModel {
        let viewModel = ScanViewModel(
            makeScan: { [arSession] in
                ScanSession(session: arSession, frameInterval: 1.0 / 15.0, supportsLiDAR: { true })
            },
            camera: FakeCameraPermission(status: .authorized),
            storageController: StorageController(inMemory: true))
        await viewModel.start()
        return viewModel
    }

    private func collect(_ viewModel: ScanViewModel, at time: Double, planes: [ScanPlane]? = nil) throws {
        viewModel.collect(from: try measuringFrame(at: time, metres: 2, planes: planes ?? floor))
    }

    @Test("P1: the plane search stays on in the first second after the floor")
    func planeSearchStaysOnInTheFirstSecond() async throws {
        let viewModel = await makeScanningViewModel()

        try collect(viewModel, at: 10)
        try collect(viewModel, at: 10.8)

        #expect(arSession.runs.count == 1)
    }

    @Test("P2: the plane search stops one second after the floor")
    func planeSearchStopsOneSecondAfterTheFloor() async throws {
        let viewModel = await makeScanningViewModel()

        try collect(viewModel, at: 10)
        try collect(viewModel, at: 11)

        #expect(arSession.runs.count == 2)
        let configuration = try #require(arSession.runs.last?.configuration as? ARWorldTrackingConfiguration)
        #expect(configuration.planeDetection == [])
    }

    @Test("P5: the floor stays after the plane search stops, even in a frame with no planes")
    func theFloorStaysAfterThePlaneSearchStops() async throws {
        let viewModel = await makeScanningViewModel()

        try collect(viewModel, at: 10)
        #expect(viewModel.currentStep != .floor)
        try collect(viewModel, at: 11)
        try collect(viewModel, at: 11.2, planes: [])

        #expect(arSession.runs.count == 2)
        #expect(viewModel.hasFloor)
        #expect(viewModel.floorY == -1)
    }
}
