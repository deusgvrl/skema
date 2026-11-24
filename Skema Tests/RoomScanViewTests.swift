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

    @Test("Apple's coaching screen (as in Measure) is on the camera view, on the scan's session")
    func coaching() throws {
        let scan = ScanSession(session: ARSession(), supportsLiDAR: { true })
        let session = try #require(scan.session as? ARSession)

        let view = RoomScanView.makeCameraView(session: session)

        let coaching = view.subviews.compactMap { $0 as? ARCoachingOverlayView }
        #expect(coaching.count == 1)
        #expect(coaching.first?.activatesAutomatically == true)
        #expect(session.delegate === scan)
        // Not checked here: the coaching screen's session and its goal (.horizontalPlane). ARKit keeps them only on a
        // session that runs world tracking with plane detection, which the Simulator does not have, and even on an
        // iPhone the goal read back depends on what earlier tests did with ARKit. Checked on an iPhone (23 Nov): on
        // the app's running scan the goal is .horizontalPlane, for a first and a second scan.
    }

    @Test("Case 25 (A10-106): the camera view draws no grounding shadows")
    func viewHasNoGroundingShadows() {
        let view = RoomScanView.makeCameraView(session: ARSession())

        #expect(view.renderOptions.contains(.disableGroundingShadows))
    }
}
