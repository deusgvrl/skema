//
//  ScanProjectionTests.swift
//  Skema Tests
//
//  Created by Amadeus Gavriel on 24/11/26.
//
//  The projection maths for the Metal camera view: 3D spot to screen point, the camera picture's texture corners,
//  and a spot's place in the picture. Shared camera: fx = fy = 1500, centre (960, 720), 1920 x 1440 picture,
//  no turn or move, shown on a 390 x 844 portrait view. The screen points were checked against ScanOverlay.
//

import CoreGraphics
import MeasureKit
import simd
import Testing
@testable import Skema_Photo

private let viewSize = CGSize(width: 390, height: 844)

private func makeCamera(focal: Float = 1500, centre: SIMD2<Float> = SIMD2(960, 720),
                        pose: simd_float4x4 = matrix_identity_float4x4) -> CameraModel {
    var intrinsics = matrix_identity_float3x3
    intrinsics[0][0] = focal
    intrinsics[1][1] = focal
    intrinsics[2][0] = centre.x
    intrinsics[2][1] = centre.y
    return CameraModel(intrinsics: intrinsics, imageResolution: SIMD2(1920, 1440), cameraToWorld: pose)
}

/// The camera at (0.5, 1.4, 1.0), turned 30 degrees about world y.
private func offCentreCamera() -> CameraModel {
    var pose = simd_float4x4(simd_quatf(angle: 30 * .pi / 180, axis: SIMD3(0, 1, 0)))
    pose.columns.3 = SIMD4(0.5, 1.4, 1.0, 1)
    return makeCamera(focal: 1340.3, centre: SIMD2(957.6, 723.1), pose: pose)
}

@Suite("Scan projection")
struct ScanProjectionTests {
    @Test("M5: a spot in front lands on the screen where ScanOverlay puts it")
    func spotInFrontLandsOnTheScreen() throws {
        let camera = makeCamera()
        let spot = SIMD3<Float>(0.1, 0.2, -2)

        let point = try #require(ScanProjection.screenPoint(of: spot, camera: camera, viewSize: viewSize))
        let overlay = try #require(ScanOverlay.screenPoint(of: spot, camera: camera, screenSize: viewSize))

        #expect(abs(point.x - 260.9375) < 0.01)
        #expect(abs(point.y - 454.96875) < 0.01)
        #expect(abs(point.x - overlay.x) < 0.01)
        #expect(abs(point.y - overlay.y) < 0.01)
    }

    @Test("M5 off-centre: a turned and moved camera with a shifted centre still matches ScanOverlay")
    func offCentreCameraMatchesScanOverlay() throws {
        let camera = offCentreCamera()
        let spot = SIMD3<Float>(-0.3, 1.1, -1.5)
        let size = CGSize(width: 402, height: 874)

        let point = try #require(ScanProjection.screenPoint(of: spot, camera: camera, viewSize: size))
        let overlay = try #require(ScanOverlay.screenPoint(of: spot, camera: camera, screenSize: size))

        #expect(abs(point.x - 128.2321) < 0.01)
        #expect(abs(point.y - 568.4360) < 0.01)
        #expect(abs(point.x - overlay.x) < 0.01)
        #expect(abs(point.y - overlay.y) < 0.01)
    }

    @Test("M6: a spot behind the camera has no screen point")
    func spotBehindTheCameraHasNoScreenPoint() {
        let camera = makeCamera()
        let spot = SIMD3<Float>(0.1, 0.2, 1)

        let clip = ScanProjection.viewProjection(camera: camera, viewSize: viewSize) * SIMD4(spot, 1)

        #expect(clip.w <= 0)
        #expect(ScanProjection.screenPoint(of: spot, camera: camera, viewSize: viewSize) == nil)
    }

    @Test("M7: the picture corners are the texture coordinates of the four screen corners")
    func pictureQuadCorners() throws {
        let camera = makeCamera()
        let corners = ScanProjection.pictureQuadTexCoords(camera: camera, viewSize: viewSize)
        // Top-left, top-right, bottom-left, bottom-right.
        let expected: [SIMD2<Float>] = [SIMD2(0, 0.808), SIMD2(0, 0.192), SIMD2(1, 0.808), SIMD2(1, 0.192)]

        #expect(corners.count == 4)
        for (corner, want) in zip(corners, expected) {
            #expect(abs(corner.x - want.x) < 0.001)
            #expect(abs(corner.y - want.y) < 0.001)
        }

        let topLeft = try #require(ScanOverlay.picturePoint(fromScreen: .zero, camera: camera, screenSize: viewSize))
        #expect(abs(Float(topLeft.x) - corners[0].x) < 0.001)
        #expect(abs(Float(topLeft.y) - corners[0].y) < 0.001)
    }

    @Test("M8: a spot's picture fraction and line depth")
    func pictureFractionAndLineDepth() throws {
        let camera = makeCamera()
        let spot = SIMD3<Float>(0.1, 0.2, -2)

        let fraction = try #require(ScanProjection.pictureFraction(of: spot, camera: camera))

        #expect(abs(fraction.x - 1035 / 1920) < 1e-4)
        #expect(abs(fraction.y - 570 / 1440) < 1e-4)
        #expect(abs(ScanProjection.lineDepth(of: spot, camera: camera) - 2) < 1e-4)
    }

    @Test("M8: a spot closer than the minimum project depth, or behind the camera, has no picture fraction")
    func pictureFractionNeedsMinimumDepth() {
        let camera = makeCamera()

        #expect(ScanProjection.pictureFraction(of: SIMD3<Float>(0, 0, -0.005), camera: camera) == nil)
        #expect(ScanProjection.pictureFraction(of: SIMD3<Float>(0, 0, 1), camera: camera) == nil)
        #expect(ScanProjection.pictureFraction(of: SIMD3<Float>(0, 0, -0.011), camera: camera) != nil)
    }

    @Test("M9: the depth row maps near to 0 and far to 1, and clip.w is the line depth")
    func depthRowMapsNearAndFar() {
        let camera = makeCamera()
        let matrix = ScanProjection.viewProjection(camera: camera, viewSize: viewSize)
        func depthValue(_ distance: Float) -> Float {
            let clip = matrix * SIMD4(0, 0, -distance, 1)
            return clip.z / clip.w
        }

        #expect(abs(depthValue(0.01)) < 1e-4)
        #expect(abs(depthValue(20) - 1) < 1e-4)
        let middle = depthValue(2)
        #expect(middle > 0 && middle < 1)
    }

    @Test("M9: clip.w is the line depth, so the shader can use it")
    func clipWIsTheLineDepth() {
        let camera = offCentreCamera()
        let spot = SIMD3<Float>(-0.3, 1.1, -1.5)

        let clip = ScanProjection.viewProjection(camera: camera, viewSize: viewSize) * SIMD4(spot, 1)

        #expect(abs(clip.w - ScanProjection.lineDepth(of: spot, camera: camera)) < 1e-4)
    }

    @Test("M9: viewProjection passes its own near and far to the depth row")
    func viewProjectionUsesGivenNearAndFar() {
        let camera = makeCamera()
        let matrix = ScanProjection.viewProjection(camera: camera, viewSize: viewSize, near: 0.1, far: 10)
        func depthValue(_ distance: Float) -> Float {
            let clip = matrix * SIMD4(0, 0, -distance, 1)
            return clip.z / clip.w
        }

        #expect(abs(depthValue(0.1)) < 1e-4)
        #expect(abs(depthValue(10) - 1) < 1e-4)
    }

    @Test("M10: the focal length is fx times the fit scale")
    func focalLengthIsFxTimesTheFitScale() {
        let camera = makeCamera()

        let focal = ScanProjection.focalLength(camera: camera, viewSize: viewSize)

        #expect(abs(focal - 659.375) < 0.01)
    }
}
