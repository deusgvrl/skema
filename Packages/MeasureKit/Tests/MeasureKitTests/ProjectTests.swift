import Testing
import simd
@testable import MeasureKit

/// 3D spot → camera picture pixel, the opposite of `DepthSampler.unproject` (A10-62 cases 9, 10, 22, 23).
/// Camera: 1920 x 1440 picture, fx = fy = 1000, centre (960, 720). ARKit camera space looks along -z.
private func camera(at origin: SIMD3<Float> = .zero) -> CameraModel {
    var intrinsics = matrix_identity_float3x3
    intrinsics[0][0] = 1000
    intrinsics[1][1] = 1000
    intrinsics[2][0] = 960
    intrinsics[2][1] = 720
    var pose = matrix_identity_float4x4
    pose.columns.3 = SIMD4(origin, 1)
    return CameraModel(intrinsics: intrinsics, imageResolution: SIMD2(1920, 1440), cameraToWorld: pose)
}

@Suite struct ProjectTests {
    // Case 9: 1 m straight in front lands on the picture centre.
    @Test func spotStraightAheadIsThePictureCentre() {
        #expect(DepthSampler.project(SIMD3(0, 0, -1), camera: camera()) == SIMD2(960, 720))
    }

    // Right of and above the centre, 1 m away: x = 960 + 1000 * 0.5 = 1460, y = 720 - 1000 * 0.25 = 470.
    @Test func spotRightAndAboveMovesRightAndUpInThePicture() {
        #expect(DepthSampler.project(SIMD3(0.5, 0.25, -1), camera: camera()) == SIMD2(1460, 470))
    }

    // The camera's position counts: a camera at z = 2 sees z = 1 as 1 m in front.
    @Test func cameraPositionIsTakenIntoAccount() {
        #expect(DepthSampler.project(SIMD3(0, 0, 1), camera: camera(at: SIMD3(0, 0, 2))) == SIMD2(960, 720))
    }

    // Case 10.
    @Test func spotBehindTheCameraHasNoPixel() {
        #expect(DepthSampler.project(SIMD3(0, 0, 1), camera: camera()) == nil)
    }

    // Case 22: x = 960 + 1000 * 5 = 5960, past the 1920-pixel picture.
    @Test func spotBesideThePictureHasNoPixel() {
        #expect(DepthSampler.project(SIMD3(5, 0, -1), camera: camera()) == nil)
    }

    // Case 23: 1 mm in front, closer than the 1 cm limit.
    @Test func spotAlmostTouchingTheCameraHasNoPixel() {
        #expect(DepthSampler.project(SIMD3(0, 0, -0.001), camera: camera()) == nil)
    }
}
