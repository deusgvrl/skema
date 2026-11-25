//
//  FieldOfView.swift
//  MeasureKit
//
//  Created by Amadeus Gavriel on 26/11/26.
//

import simd

/// A10-121: can a world box be in the camera picture? A quick rule to skip work for things the camera cannot see.
public enum FieldOfView {
    /// False only when the whole box is out of the picture: all 8 corners are on the wrong side of the same edge
    /// of the view (behind the camera, or left, right, above or below the picture). Otherwise true.
    /// It is careful on purpose: a box near a corner of the picture can pass without being seen. That only costs
    /// one extra pass, and it never hides a box the camera can see (a big box across the view, or around the camera):
    /// every edge of the view is a flat wall through the camera, so a solid box with all 8 corners past one wall is
    /// wholly past it.
    /// Same camera conventions as `DepthSampler.project`.
    public static func contains(_ box: WorldBox, camera: CameraModel) -> Bool {
        let toCamera = camera.cameraToWorld.inverse
        let k = camera.intrinsics
        let fx = k[0][0], fy = k[1][1], cx = k[2][0], cy = k[2][1]
        let width = camera.imageResolution.x, height = camera.imageResolution.y

        // One flag per edge of the view: stays true while every corner so far is outside that edge.
        var allBehind = true, allLeft = true, allRight = true, allAbove = true, allBelow = true
        for corner in box.corners {
            let local = toCamera * SIMD4<Float>(corner, 1)
            let depth = -local.z                                   // ARKit camera space looks along -z
            let sideways = fx * local.x + cx * depth               // pixel x times depth
            let upwards = -fy * local.y + cy * depth               // pixel y times depth
            allBehind = allBehind && depth < DepthSampler.minProjectDepth
            allLeft = allLeft && sideways < 0
            allRight = allRight && sideways > width * depth
            allAbove = allAbove && upwards < 0
            allBelow = allBelow && upwards > height * depth
        }
        return !(allBehind || allLeft || allRight || allAbove || allBelow)
    }
}
