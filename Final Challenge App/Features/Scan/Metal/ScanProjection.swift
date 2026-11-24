//
//  ScanProjection.swift
//  Final Challenge App
//
//  Created by Amadeus Gavriel on 24/11/26.
//
//  The projection maths for the Metal camera view. It gives the same screen points as ScanOverlay, but as one matrix,
//  so the GPU can draw the 3D parts. Portrait only. The formulas are in the "Scan Projection Maths" page.
//

import CoreGraphics
import MeasureKit
import simd

/// Pure maths with no state, so it needs no actor (the render code calls it from its own queue).
/// `viewSize` and `camera.imageResolution` must be above 0 in both sides: the fit divides by them.
/// The camera picture is sideways (width W, height H). The screen shows it upright, scaled to fill, from the centre.
nonisolated enum ScanProjection {
    /// How the upright picture sits on the view: one scale for both sides, and how far it is moved on each side.
    private struct Fit {
        let scale: Float
        let offsetX: Float
        let offsetY: Float

        init(camera: CameraModel, viewSize: CGSize) {
            let width = Float(viewSize.width)
            let height = Float(viewSize.height)
            let pictureWidth = camera.imageResolution.x
            let pictureHeight = camera.imageResolution.y
            scale = max(width / pictureHeight, height / pictureWidth)
            offsetX = (width - pictureHeight * scale) / 2
            offsetY = (height - pictureWidth * scale) / 2
        }
    }

    /// Camera space → clip space, for the upright picture that fills the view.
    /// Camera space looks down -z, so the depth of a spot is -z.
    static func projectionMatrix(camera: CameraModel, viewSize: CGSize,
                                 near: Float = 0.01, far: Float = 20) -> simd_float4x4 {
        let width = Float(viewSize.width)
        let height = Float(viewSize.height)
        let fit = Fit(camera: camera, viewSize: viewSize)
        let focalX = camera.intrinsics[0][0]
        let focalY = camera.intrinsics[1][1]
        let centreX = camera.intrinsics[2][0]
        let centreY = camera.intrinsics[2][1]

        let xFromY = 2 * fit.scale * focalY / width
        let xShift = 2 * (fit.scale * (camera.imageResolution.y - centreY) + fit.offsetX) / width - 1
        let yFromX = 2 * fit.scale * focalX / height
        let yShift = 1 - 2 * (fit.scale * centreX + fit.offsetY) / height
        let depthScale = -far / (far - near)
        let depthShift = -far * near / (far - near)

        // The rows (xFromY, xShift, yFromX, yShift are a, b, e, g on the maths page).
        return simd_float4x4(rows: [
            SIMD4(0, xFromY, -xShift, 0),
            SIMD4(-yFromX, 0, -yShift, 0),
            SIMD4(0, 0, depthScale, depthShift),
            SIMD4(0, 0, -1, 0)
        ])
    }

    /// World space → clip space. `near` and `far` (in metres) set the depth row: near gives 0, far gives 1.
    static func viewProjection(camera: CameraModel, viewSize: CGSize,
                               near: Float = 0.01, far: Float = 20) -> simd_float4x4 {
        projectionMatrix(camera: camera, viewSize: viewSize, near: near, far: far) * camera.cameraToWorld.inverse
    }

    /// The focal length in view points: fx times the fit scale (the scale the matrix uses). It is the same value
    /// `RoomScanView.focalLength(of:)` gives for an ARView.
    static func focalLength(camera: CameraModel, viewSize: CGSize) -> Float {
        camera.intrinsics[0][0] * Fit(camera: camera, viewSize: viewSize).scale
    }

    /// A 3D spot → its point on the view. Nil when the spot is behind the camera. The point may be off the view.
    static func screenPoint(of world: SIMD3<Float>, camera: CameraModel, viewSize: CGSize) -> CGPoint? {
        let clip = viewProjection(camera: camera, viewSize: viewSize) * SIMD4(world, 1)
        guard clip.w > 0 else { return nil }
        let ndcX = clip.x / clip.w
        let ndcY = clip.y / clip.w
        return CGPoint(x: CGFloat((ndcX + 1) / 2) * viewSize.width,
                       y: CGFloat((1 - ndcY) / 2) * viewSize.height)
    }

    /// Where the four view corners fall in the camera picture, as (x, y) fractions of the sideways picture.
    /// Order: top-left, top-right, bottom-left, bottom-right. A corner may fall outside the picture (no check).
    static func pictureQuadTexCoords(camera: CameraModel, viewSize: CGSize) -> [SIMD2<Float>] {
        let fit = Fit(camera: camera, viewSize: viewSize)
        let width = Float(viewSize.width)
        let height = Float(viewSize.height)
        let pictureWidth = camera.imageResolution.x
        let pictureHeight = camera.imageResolution.y
        let corners: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(width, 0), SIMD2(0, height), SIMD2(width, height)]
        return corners.map { corner in
            // Upright picture point (u, v), then the sideways picture's (v, H - u).
            let uprightX = (corner.x - fit.offsetX) / fit.scale
            let uprightY = (corner.y - fit.offsetY) / fit.scale
            return SIMD2(uprightY / pictureWidth, (pictureHeight - uprightX) / pictureHeight)
        }
    }

    /// A 3D spot → its place in the camera picture, as (x, y) fractions of the sideways picture.
    /// Nil when the spot is closer than `DepthSampler.minProjectDepth` (or behind the camera), like ScanOverlay.
    static func pictureFraction(of world: SIMD3<Float>, camera: CameraModel) -> SIMD2<Float>? {
        let local = camera.cameraToWorld.inverse * SIMD4(world, 1)
        let depth = -local.z
        guard depth >= DepthSampler.minProjectDepth else { return nil }
        let pixelX = camera.intrinsics[0][0] * local.x / depth + camera.intrinsics[2][0]
        let pixelY = camera.intrinsics[1][1] * -local.y / depth + camera.intrinsics[2][1]
        return SIMD2(pixelX / camera.imageResolution.x, pixelY / camera.imageResolution.y)
    }

    /// How far a spot is in front of the camera (-z in camera space). Negative when it is behind.
    static func lineDepth(of world: SIMD3<Float>, camera: CameraModel) -> Float {
        -(camera.cameraToWorld.inverse * SIMD4(world, 1)).z
    }
}
