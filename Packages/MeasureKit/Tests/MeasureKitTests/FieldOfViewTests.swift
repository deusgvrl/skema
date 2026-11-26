//
//  FieldOfViewTests.swift
//  MeasureKit
//
//  Created by Amadeus Gavriel on 26/11/26.
//

import Testing
import simd
@testable import MeasureKit

/// A10-121 cases V1-V6: can a world box be in the camera picture? Camera at the origin, looking along -z,
/// picture 1920 x 1440 px, fx = fy = 1000, principal point (960, 720).
@Suite("Field of view (A10-121)")
struct FieldOfViewTests {
    private let camera = CameraModel(
        intrinsics: simd_float3x3(columns: (SIMD3<Float>(1000, 0, 0), SIMD3<Float>(0, 1000, 0), SIMD3<Float>(960, 720, 1))),
        imageResolution: SIMD2<Float>(1920, 1440),
        cameraToWorld: matrix_identity_float4x4)

    /// A 20 cm cube around `centre`.
    private func cube(at centre: SIMD3<Float>) -> WorldBox {
        WorldBox(min: centre - SIMD3<Float>(repeating: 0.1), max: centre + SIMD3<Float>(repeating: 0.1))
    }

    @Test("V1: a box ahead of the camera is in view")
    func aBoxAheadIsInView() {
        #expect(FieldOfView.contains(cube(at: SIMD3(0, 0, -2)), camera: camera))
    }

    @Test("V2: a box behind the camera is not in view")
    func aBoxBehindIsNotInView() {
        #expect(!FieldOfView.contains(cube(at: SIMD3(0, 0, 2)), camera: camera))
    }

    @Test("V2b: a wide box behind the camera is not in view, even when no side wall alone hides it")
    func aWideBoxBehindIsNotInView() {
        let box = WorldBox(min: SIMD3(-10, -10, 1), max: SIMD3(10, 10, 2))
        #expect(!FieldOfView.contains(box, camera: camera))
    }

    @Test("V3: a box beside the picture is not in view", arguments: [
        SIMD3<Float>(-5, 0, -2), SIMD3<Float>(5, 0, -2), SIMD3<Float>(0, 5, -2), SIMD3<Float>(0, -5, -2)
    ])
    func aBoxBesideThePictureIsNotInView(centre: SIMD3<Float>) {
        #expect(!FieldOfView.contains(cube(at: centre), camera: camera))
    }

    @Test("V4: a big box across the view is in view, even when every corner is outside the picture")
    func aBigBoxAcrossTheViewIsInView() {
        let box = WorldBox(min: SIMD3(-10, -10, -3), max: SIMD3(10, 10, -2.5))
        #expect(FieldOfView.contains(box, camera: camera))
    }

    @Test("V5: a box around the camera is in view")
    func aBoxAroundTheCameraIsInView() {
        let box = WorldBox(min: SIMD3(-1, -1, -1), max: SIMD3(1, 1, 1))
        #expect(FieldOfView.contains(box, camera: camera))
    }

    @Test("V6: a box with only a few corners inside the picture is in view")
    func aBoxWithFewCornersInsideIsInView() {
        let box = WorldBox(min: SIMD3(0.9, 0.6, -2.2), max: SIMD3(3, 3, -2))
        #expect(FieldOfView.contains(box, camera: camera))
    }
}
