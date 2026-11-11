//
//  RoomPoints.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 11/11/26.
//

import Foundation
import MeasureKit
import simd

nonisolated struct RoomPoint: Equatable, Sendable {
    /// ARKit world position in metres. It stays put while the user walks.
    let world: SIMD3<Float>
    /// Red (near) → yellow → green → blue (far), from `DepthPalette`.
    let rgb: SIMD3<UInt8>
}

nonisolated struct RoomPoints: Sendable {
    /// Every 4th depth pixel in both directions, like the PoC preview.
    static let pixelStride = 4
    /// Points farther than the measuring range are not shown.
    static let maxRange = DepthSampler.maxRange

    private var cloud = ScanCloud()

    var count: Int { cloud.count }

    /// Adds one frame's LiDAR points and returns only the new ones, so the screen draws just those.
    mutating func add(depth: DepthFrame, camera: CameraModel) -> [RoomPoint] {
        let dots = DepthPreview.dots(from: depth, stride: Self.pixelStride).filter { $0.depth <= Self.maxRange }
        let new = dots.map { dot in
            let pixel = SIMD2(dot.u * camera.imageResolution.x, dot.v * camera.imageResolution.y)
            let world = DepthSampler.unproject(pixel: pixel, depth: dot.depth, camera: camera)
            let rgb = DepthPalette.rgb(DepthPreview.colorPosition(depth: dot.depth))
            return (world: world, rgb: rgb)
        }
        return cloud.add(new).map { RoomPoint(world: $0.world, rgb: $0.rgb) }
    }
}

actor RoomPointsCollector {
    private var points = RoomPoints()

    /// The new points from this frame. Empty when the frame has no depth.
    func add(_ frame: ScanFrame) -> [RoomPoint] {
        guard let depth = frame.depth else { return [] }
        return points.add(depth: depth, camera: frame.camera)
    }
}
