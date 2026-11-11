//
//  PointCloudSceneTests.swift
//  Skema Tests
//
//  Created by Muhammad Dzakki Abdullah on 11/11/26.
//

import Foundation
import ARKit
import SceneKit
import Testing
@testable import Final_Challenge_App

@MainActor
@Suite("Point cloud scene: drawing the room points")
struct PointCloudSceneTests {
    let points = [
        RoomPoint(world: SIMD3(0, 0, -1), rgb: SIMD3(255, 0, 0)),
        RoomPoint(world: SIMD3(0.1, 0, -1), rgb: SIMD3(0, 255, 0)),
        RoomPoint(world: SIMD3(0.2, 0, -1), rgb: SIMD3(0, 0, 255))
    ]

    @Test("Each point is one coloured dot, not shaded by lights")
    func geometry() throws {
        let geometry = PointCloudScene.geometry(for: points)

        let element = try #require(geometry.elements.first)
        #expect(geometry.sources(for: .vertex).first?.vectorCount == 3)
        #expect(geometry.sources(for: .color).first?.vectorCount == 3)
        #expect(element.primitiveType == .point)
        #expect(element.primitiveCount == 3)
        #expect(geometry.firstMaterial?.lightingModel == .constant)
    }

    @Test("Each batch becomes one node")
    func oneNodePerBatch() {
        let cloud = PointCloudScene()

        cloud.add(points)
        cloud.add([])

        #expect(cloud.scene.rootNode.childNodes.count == 1)
        #expect(cloud.pointCount == 3)
    }

    @Test("The camera view leaves the session's delegate to ScanSession")
    func viewKeepsDelegate() throws {
        let scan = ScanSession(session: ARSession(), supportsLiDAR: { true })
        let session = try #require(scan.session as? ARSession)

        let view = ARSCNView(frame: .zero)
        view.session = session

        #expect(session.delegate === scan)
    }
}
