//
//  RoomScanViewTests.swift
//  Skema Tests
//
//  Created by Muhammad Dzakki Abdullah on 13/11/26.
//

import ARKit
import Testing
@testable import Final_Challenge_App

@MainActor
@Suite("Room scan view: the live camera")
struct RoomScanViewTests {
    @Test("The camera view leaves the session's delegate to ScanSession")
    func viewKeepsDelegate() throws {
        let scan = ScanSession(session: ARSession(), supportsLiDAR: { true })
        let session = try #require(scan.session as? ARSession)

        let view = ARSCNView(frame: .zero)
        view.session = session

        #expect(session.delegate === scan)
    }
}
