//
//  ScanOverlayTests.swift
//  Skema Tests
//
//  Where a 3D spot's tag goes on the screen, where a tap lands in the picture, and the Finish Scan rule
//  (the A10-62 cases the scan still uses; the detection cases went with object detection, 19 Nov 2026).
//  Camera: 1920 x 1440 sideways picture, fx = fy = 1000, centre (960, 720), shown upright (portrait).
//  The screen is 1440 x 1920, the same size as the upright picture, so its centre is (720, 960).
//

import CoreGraphics
import MeasureKit
import simd
import Testing
@testable import Skema_Photo

private let screen = CGSize(width: 1440, height: 1920)

private func camera(facingBack: Bool = false) -> CameraModel {
    var intrinsics = matrix_identity_float3x3
    intrinsics[0][0] = 1000
    intrinsics[1][1] = 1000
    intrinsics[2][0] = 960
    intrinsics[2][1] = 720
    var pose = matrix_identity_float4x4
    if facingBack {
        pose.columns.0 = SIMD4(-1, 0, 0, 0)
        pose.columns.2 = SIMD4(0, 0, -1, 0)
    }
    return CameraModel(intrinsics: intrinsics, imageResolution: SIMD2(1920, 1440), cameraToWorld: pose)
}

private func tag(at spot: SIMD3<Float>, camera: CameraModel = camera()) -> CGPoint? {
    ScanOverlay.screenPoint(of: spot, camera: camera, screenSize: screen)
}

@Suite("Scan overlay: tags, taps and Finish Scan")
struct ScanOverlayTests {
    // MARK: Tag position

    @Test("Case 9: an item 1 m straight in front has its tag at the centre of the screen")
    func tagInFrontIsAtTheCentre() {
        #expect(tag(at: SIMD3(0, 0, -1)) == CGPoint(x: 720, y: 960))
    }

    @Test("Case 10: an item behind the camera has no tag on screen")
    func itemBehindHasNoTag() {
        #expect(tag(at: SIMD3(0, 0, 1)) == nil)
    }

    @Test("Case 22: an item beside the camera, outside the picture, has no tag on screen")
    func itemBesideHasNoTag() {
        #expect(tag(at: SIMD3(5, 0, -1)) == nil)
    }

    @Test("Case 23: an item almost touching the camera gives no crash and no tag")
    func itemTouchingHasNoTag() {
        #expect(tag(at: SIMD3(0, 0, -0.001)) == nil)
    }

    @Test("Case 11: an item that left the view gets its tag back when the camera turns back")
    func tagComesBackWhenTheCameraReturns() {
        #expect(tag(at: SIMD3(0, 0, -1), camera: camera(facingBack: true)) == nil)
        #expect(tag(at: SIMD3(0, 0, -1), camera: camera()) == CGPoint(x: 720, y: 960))
    }

    // MARK: Finish Scan

    @Test("Case 16: Finish Scan is enabled with 1 subject, 1 camera and 1 light")
    func finishEnabled() {
        #expect(ScanOverlay.canFinish(hasSubject: true, acceptedCameras: 1, acceptedLights: 1))
    }

    @Test("Case 17: no Finish Scan without a subject")
    func noFinishWithoutSubject() {
        #expect(!ScanOverlay.canFinish(hasSubject: false, acceptedCameras: 1, acceptedLights: 1))
    }

    @Test("Case 18: no Finish Scan without a camera")
    func noFinishWithoutCamera() {
        #expect(!ScanOverlay.canFinish(hasSubject: true, acceptedCameras: 0, acceptedLights: 1))
    }

    @Test("Case 19: no Finish Scan without a light")
    func noFinishWithoutLight() {
        #expect(!ScanOverlay.canFinish(hasSubject: true, acceptedCameras: 1, acceptedLights: 0))
    }

    // MARK: Tap on the screen

    @Test("A tap in the middle of the screen is the middle of the picture")
    func tapInTheMiddle() throws {
        let point = try #require(ScanOverlay.picturePoint(fromScreen: CGPoint(x: 720, y: 960), camera: camera(),
                                                         screenSize: screen))
        #expect(abs(point.x - 0.5) < 1e-6 && abs(point.y - 0.5) < 1e-6)
    }

    @Test("A tap on an item's tag spot gives the picture point that spot projects to")
    func tapIsTheInverseOfScreenPoint() throws {
        let spot = SIMD3<Float>(0.3, -0.2, -1)
        let cam = camera()
        let tapped = try #require(ScanOverlay.screenPoint(of: spot, camera: cam, screenSize: screen))
        let pixel = try #require(DepthSampler.project(spot, camera: cam))

        let point = try #require(ScanOverlay.picturePoint(fromScreen: tapped, camera: cam, screenSize: screen))

        #expect(abs(Float(point.x) - pixel.x / cam.imageResolution.x) < 1e-4)
        #expect(abs(Float(point.y) - pixel.y / cam.imageResolution.y) < 1e-4)
    }

    @Test("A tap outside the screen is nothing")
    func tapOutsideTheScreen() {
        #expect(ScanOverlay.picturePoint(fromScreen: CGPoint(x: -1, y: 5), camera: camera(), screenSize: screen) == nil)
    }
}
