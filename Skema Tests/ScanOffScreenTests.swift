//
//  ScanOffScreenTests.swift
//  Skema Tests
//
//  Created by Amadeus Gavriel on 26/11/26.
//
//  A10-121 cases O1–O5 and O8: the scan measures only the items in view, and an item out of view keeps everything it
//  has. Camera and screen as in ScanGrownBoxTests: the screen is the upright picture at scale 1, depth is a flat wall
//  2 m ahead, and every frame shows ARKit's floor 1 m below the phone. A turned frame has the same wall and floor, but
//  the phone is rotated: yaw about y (π = looking backwards), then pitch about x (positive = looking up).
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
/// World (0.768, 0, -2): where the light is tapped.
private let lightSpot = CGPoint(x: 720, y: 1344)

@MainActor
@Suite("A10-121 the scan measures only the items in view")
struct ScanOffScreenTests {
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

    /// The same frame as `measuringFrame`, with the phone turned.
    private func turnedFrame(at time: Double, yaw: Float = 0, pitch: Float = 0,
                             cameraX: Float = 0) throws -> ScanFrame {
        let straight = try measuringFrame(at: time, metres: 2, planes: planes, cameraX: cameraX)
        var pose = simd_float4x4(simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)))
            * simd_float4x4(simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0)))
        pose.columns.3 = SIMD4(cameraX, 0, 0, 1)
        let camera = CameraModel(intrinsics: straight.camera.intrinsics,
                                 imageResolution: straight.camera.imageResolution, cameraToWorld: pose)
        return ScanFrame(timestamp: time, camera: camera, depth: straight.depth, tracking: .normal,
                         ambientIntensity: nil, planes: planes)
    }

    /// A tap, then (phase 3: one item at a time) a walk around what it set, so the next tap is not held back.
    private func tap(_ viewModel: ScanViewModel, at point: CGPoint, at time: Double = 0) throws {
        let subjectBefore = viewModel.subject
        let itemsBefore = viewModel.items.count
        viewModel.tap(atScreen: point, screenSize: screen, in: try measuringFrame(at: time, metres: 2, planes: planes))
        try walkAroundNewest(viewModel, subjectBefore: subjectBefore, itemsBefore: itemsBefore, planes: planes)
    }

    /// Subject and camera tapped (the floor is found from the frames).
    private func scanWithCamera() throws -> ScanViewModel {
        let viewModel = makeViewModel()
        try tap(viewModel, at: middle)
        try tap(viewModel, at: cameraSpot)
        return viewModel
    }

    /// Subject, camera and light tapped.
    private func scanWithCameraAndLight() throws -> ScanViewModel {
        let viewModel = try scanWithCamera()
        try tap(viewModel, at: lightSpot, at: 1)
        return viewModel
    }

    private func item(_ kind: ScanTapKind, in viewModel: ScanViewModel) throws -> ScanItem {
        try #require(viewModel.items.first { $0.kind == kind })
    }

    @Test("O1: items behind the camera are not sampled")
    func anItemBehindTheCameraIsNotSampled() throws {
        let viewModel = try scanWithCamera()
        let camera = try item(.camera, in: viewModel)

        let sampled = viewModel.collect(from: try turnedFrame(at: 2, yaw: .pi))

        #expect(!sampled.contains(viewModel.subjectID))
        #expect(!sampled.contains(camera.id))
    }

    @Test("O1-light: a light whose tap is off the picture is not sampled")
    func aLightWhoseTapIsOffThePictureIsNotSampled() throws {
        let viewModel = try scanWithCameraAndLight()
        let light = try item(.light, in: viewModel)

        let sampled = viewModel.collect(from: try turnedFrame(at: 2, yaw: .pi))

        #expect(!sampled.contains(light.id))
    }

    @Test("O2: items in view are sampled")
    func anItemInViewIsSampled() throws {
        let viewModel = try scanWithCamera()
        let camera = try item(.camera, in: viewModel)

        let sampled = viewModel.collect(from: try measuringFrame(at: 2, metres: 2, planes: planes))

        #expect(sampled.contains(viewModel.subjectID))
        #expect(sampled.contains(camera.id))
    }

    @Test("O3: a tall item whose tapped point is below the picture is still sampled")
    func aTallItemWhoseTapIsBelowThePictureIsSampled() throws {
        let viewModel = try scanWithCamera()
        let camera = try item(.camera, in: viewModel)
        // The phone looks up 60 degrees: the tap (height 0) is below the picture, the top of the 3 m tube is in it.
        let frame = try turnedFrame(at: 2, pitch: .pi / 3)
        try #require(DepthSampler.project(camera.anchor, camera: frame.camera) == nil)

        let sampled = viewModel.collect(from: frame)

        #expect(sampled.contains(camera.id))
    }

    @Test("O4: items out of view keep their results, their boxes and Finish")
    func anOffScreenItemKeepsWhatItHas() throws {
        let viewModel = try scanWithCameraAndLight()
        let results = viewModel.items.map(\.result)
        let itemBounds = viewModel.itemBounds
        let subjectBounds = viewModel.subjectBounds
        let subjectResult = viewModel.subjectResult
        try #require(subjectBounds != nil)
        try #require(subjectResult != nil)
        try #require(results.allSatisfy { $0?.pointCount ?? 0 > 0 })
        try #require(itemBounds.count == 2)
        try #require(viewModel.canFinish)

        for frame in 0..<5 {
            viewModel.collect(from: try turnedFrame(at: 2 + Double(frame) * 0.2, yaw: .pi))
        }

        #expect(viewModel.items.map(\.result) == results)
        #expect(viewModel.itemBounds == itemBounds)
        #expect(viewModel.subjectBounds == subjectBounds)
        #expect(viewModel.subjectResult == subjectResult)
        #expect(viewModel.canFinish)
    }

    @Test("O4-light (review fix): a painted light's outline follows its grown box, also with no new points")
    func aLightsOutlineFollowsItsGrownBox() throws {
        // The tap frame paints the wall from x = -1.92 to 1.92 m. Frames from 1 m to the right paint -0.92 to 2.92 m:
        // the first one adds new points, the rest add none, but each adds a small box. After 30 of them the tap
        // frame's box is the oldest of 31 and drops out (`ScanMeasurements.maxKeptBoxes`), so the grown box loses
        // its left part.
        let viewModel = try scanWithCameraAndLight()
        let light = try item(.light, in: viewModel)

        for frame in 0..<ScanMeasurements.maxKeptBoxes {
            viewModel.collect(from: try measuringFrame(at: 2 + Double(frame) * 0.2, metres: 2, planes: planes,
                                                       cameraX: 1))
        }

        let outline = try #require(viewModel.itemBounds[light.id])
        #expect(outline.min.x > -1)
    }

    @Test("O5: an item back in view collects again")
    func anItemBackInViewContinues() throws {
        let viewModel = try scanWithCameraAndLight()
        let camera = try item(.camera, in: viewModel)
        let before = try #require(try item(.camera, in: viewModel).result?.pointCount)
        for frame in 0..<5 {
            viewModel.collect(from: try turnedFrame(at: 2 + Double(frame) * 0.2, yaw: .pi))
        }

        viewModel.collect(from: try measuringFrame(at: 4, metres: 2, planes: planes, cameraX: 0.015))

        let after = try #require(viewModel.items.first { $0.id == camera.id }?.result?.pointCount)
        #expect(after > before)
    }

    @Test("O8: a frame with no new points keeps the result")
    func noNewPointsKeepTheResult() throws {
        let viewModel = try scanWithCamera()

        viewModel.collect(from: try measuringFrame(at: 2, metres: 2, planes: planes))
        let first = try item(.camera, in: viewModel).result
        viewModel.collect(from: try measuringFrame(at: 2.2, metres: 2, planes: planes))

        #expect(try item(.camera, in: viewModel).result == first)
        #expect(first != nil)
    }
}
