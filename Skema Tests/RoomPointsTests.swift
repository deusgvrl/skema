//
//  RoomPointsTests.swift
//  Skema Tests
//
//  Created by Muhammad Dzakki Abdullah on 11/11/26.
//

import Foundation
import MeasureKit
import simd
import Testing
@testable import Final_Challenge_App

/// A depth frame where every pixel has the same depth and confidence.
func makeDepth(width: Int, height: Int, depth: Float, confidence: UInt8 = 2) -> DepthFrame {
    DepthFrame(
        width: width,
        height: height,
        depth: [Float](repeating: depth, count: width * height),
        confidence: [UInt8](repeating: confidence, count: width * height)
    )
}

/// A pinhole camera looking down -Z, with the image centre in the middle.
func makeCamera(size: Float, focal: Float, position: SIMD3<Float> = .zero) -> CameraModel {
    var cameraToWorld = matrix_identity_float4x4
    cameraToWorld.columns.3 = SIMD4(position, 1)
    return CameraModel(
        intrinsics: simd_float3x3(columns: (
            SIMD3(focal, 0, 0),
            SIMD3(0, focal, 0),
            SIMD3(size / 2, size / 2, 1)
        )),
        imageResolution: SIMD2(size, size),
        cameraToWorld: cameraToWorld
    )
}

@Suite("Room points: LiDAR points fixed in the room")
struct RoomPointsTests {
    @Test("Every 4th depth pixel becomes a world point")
    func everyFourthPixel() {
        var room = RoomPoints()

        let added = room.add(depth: makeDepth(width: 8, height: 8, depth: 1), camera: makeCamera(size: 8, focal: 8))

        #expect(added.count == 4)
        #expect(room.count == 4)
        #expect(added.allSatisfy { abs($0.world.z + 1) < 0.0001 })
    }

    @Test("Near is red and far is blue", arguments: [
        (Float(0.3), SIMD3<UInt8>(255, 0, 0)),
        (Float(4), SIMD3<UInt8>(0, 0, 255))
    ])
    func colours(depth: Float, expected: SIMD3<UInt8>) {
        var room = RoomPoints()

        let added = room.add(depth: makeDepth(width: 1, height: 1, depth: depth), camera: makeCamera(size: 1, focal: 1))

        #expect(added.map(\.rgb) == [expected])
    }

    @Test("Low-confidence pixels are skipped")
    func lowConfidence() {
        var room = RoomPoints()

        let added = room.add(
            depth: makeDepth(width: 8, height: 8, depth: 1, confidence: 1),
            camera: makeCamera(size: 8, focal: 8)
        )

        #expect(added.isEmpty)
    }

    @Test("Points beyond the 5 m range are skipped", arguments: [(Float(5), 1), (Float(6), 0)])
    func range(depth: Float, expectedCount: Int) {
        var room = RoomPoints()

        let added = room.add(depth: makeDepth(width: 1, height: 1, depth: depth), camera: makeCamera(size: 1, focal: 1))

        #expect(added.count == expectedCount)
    }

    @Test("The same frame twice adds nothing the second time")
    func sameFrameTwice() {
        var room = RoomPoints()
        let depth = makeDepth(width: 8, height: 8, depth: 1)
        let camera = makeCamera(size: 8, focal: 8)
        _ = room.add(depth: depth, camera: camera)

        let second = room.add(depth: depth, camera: camera)

        #expect(second.isEmpty)
        #expect(room.count == 4)
    }

    @Test("A spot seen from two places is one point: points stay fixed in the room")
    func fixedInRoom() {
        var room = RoomPoints()
        // The wall is 1 m in front of the start position.
        let first = room.add(depth: makeDepth(width: 1, height: 1, depth: 1), camera: makeCamera(size: 1, focal: 1))

        // The user steps back 1 m. The same spot is now 2 m away.
        let steppedBack = makeCamera(size: 1, focal: 1, position: SIMD3(0, 0, 1))
        let second = room.add(depth: makeDepth(width: 1, height: 1, depth: 2), camera: steppedBack)

        #expect(first.map(\.world) == [SIMD3(0, 0, -1)])
        #expect(second.isEmpty)
    }

    @Test("A new spot after walking is added")
    func newSpotAfterWalking() {
        var room = RoomPoints()
        _ = room.add(depth: makeDepth(width: 1, height: 1, depth: 1), camera: makeCamera(size: 1, focal: 1))

        let steppedBack = makeCamera(size: 1, focal: 1, position: SIMD3(0, 0, 1))
        let added = room.add(depth: makeDepth(width: 1, height: 1, depth: 1), camera: steppedBack)

        #expect(added.map(\.world) == [SIMD3(0, 0, 0)])
        #expect(room.count == 2)
    }

    @Test("A frame without depth adds nothing")
    func frameWithoutDepth() async throws {
        let collector = RoomPointsCollector()

        let added = await collector.add(try makeScanFrame(timestamp: 0))

        #expect(added.isEmpty)
    }
}
