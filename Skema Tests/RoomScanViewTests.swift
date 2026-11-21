//
//  RoomScanViewTests.swift
//  Skema Tests
//
//  Created by Muhammad Dzakki Abdullah on 13/11/26.
//

import ARKit
import RealityKit
import Testing
@testable import Skema_Photo

@MainActor
@Suite("Room scan view: the live camera")
struct RoomScanViewTests {
    @Test("The camera view shows the scan's own session and leaves its delegate to ScanSession")
    func viewKeepsDelegate() throws {
        let scan = ScanSession(session: ARSession(), supportsLiDAR: { true })
        let session = try #require(scan.session as? ARSession)

        // A10-106: the camera view is RealityKit's ARView now (it was ARSCNView), for the 3D outline's occlusion.
        let view = RoomScanView.makeCameraView(session: session)

        #expect(view.session === session)
        #expect(session.delegate === scan)
    }
}
