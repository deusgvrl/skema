//
//  ScanFrame.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 10/11/26.
//

import CoreVideo
import Foundation
import MeasureKit

nonisolated struct ScanFrame: @unchecked Sendable {

    let timestamp: TimeInterval
    let image: CVPixelBuffer
    let orientation: ImageOrientation
    let camera: CameraModel
    let depth: DepthFrame?
    let tracking: ScanTracking
    let ambientIntensity: Float?
    let planes: [ScanPlane]
}

nonisolated struct ScanPlane: Equatable, Sendable {
    let id: UUID
    let worldY: Float
    let isFloor: Bool
    let area: Float

    var horizontalPlane: HorizontalPlane {
        HorizontalPlane(y: worldY, isFloor: isFloor)
    }
}

nonisolated enum ScanTracking: Equatable, Sendable {
    case normal
    case limited(Reason)
    case notAvailable

    enum Reason: Equatable, Sendable {
        case initializing
        case excessiveMotion
        case insufficientFeatures
        case relocalizing
        case other
    }
}
