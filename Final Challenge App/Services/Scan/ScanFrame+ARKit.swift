//
//  ScanFrame+ARKit.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 10/11/26.
//

import Foundation
import ARKit
import MeasureKit

nonisolated extension ScanFrame {
    init(_ frame: ARFrame, planes: [ScanPlane]) {
        self.init(
            timestamp: frame.timestamp,
            image: frame.capturedImage,
            orientation: .right,
            camera: CameraModel(frame.camera),
            depth: frame.sceneDepth.flatMap {
                DepthCopier.copy(depthMap: $0.depthMap, confidenceMap: $0.confidenceMap)
            },
            tracking: ScanTracking(frame.camera.trackingState),
            ambientIntensity: frame.lightEstimate.map { Float($0.ambientIntensity) },
            planes: planes
        )
    }
}

nonisolated extension CameraModel {
    init(_ camera: ARCamera) {
        self.init(
            intrinsics: camera.intrinsics,
            imageResolution: SIMD2(Float(camera.imageResolution.width), Float(camera.imageResolution.height)),
            cameraToWorld: camera.transform
        )
    }
}

nonisolated extension ScanPlane {
    init?(_ anchor: ARAnchor) {
        guard let plane = anchor as? ARPlaneAnchor, plane.alignment == .horizontal else { return nil }
        let centre = plane.transform * SIMD4<Float>(plane.center, 1)
        self.init(
            id: plane.identifier,
            worldY: centre.y,
            isFloor: plane.classification == .floor,
            area: plane.planeExtent.width * plane.planeExtent.height
        )
    }
}

nonisolated extension ScanTracking {
    init(_ state: ARCamera.TrackingState) {
        switch state {
        case .normal:
            self = .normal
        case .notAvailable:
            self = .notAvailable
        case .limited(.initializing):
            self = .limited(.initializing)
        case .limited(.excessiveMotion):
            self = .limited(.excessiveMotion)
        case .limited(.insufficientFeatures):
            self = .limited(.insufficientFeatures)
        case .limited(.relocalizing):
            self = .limited(.relocalizing)
        case .limited:
            self = .limited(.other)
        }
    }
}
