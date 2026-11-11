//
//  PointCloudScene.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 11/11/26.
//

import Foundation
import SceneKit

/// Each batch of new points becomes one node, so points already drawn are never rebuilt.
final class PointCloudScene {
    let scene = SCNScene()
    private(set) var pointCount = 0

    func add(_ points: [RoomPoint]) {
        guard !points.isEmpty else { return }
        scene.rootNode.addChildNode(SCNNode(geometry: Self.geometry(for: points)))
        pointCount += points.count
    }

    /// Dots that keep a fixed size on screen, coloured per point and not shaded by lights.
    static func geometry(for points: [RoomPoint]) -> SCNGeometry {
        let positions = SCNGeometrySource(vertices: points.map { SCNVector3($0.world.x, $0.world.y, $0.world.z) })
        let colorValues = points.flatMap { point in
            [Float(point.rgb.x), Float(point.rgb.y), Float(point.rgb.z)].map { $0 / 255 }
        }
        let colors = SCNGeometrySource(
            data: colorValues.withUnsafeBufferPointer { Data(buffer: $0) },
            semantic: .color,
            vectorCount: points.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 3
        )
        let dots = SCNGeometryElement(indices: Array(0..<UInt32(points.count)), primitiveType: .point)
        dots.pointSize = 6
        dots.minimumPointScreenSpaceRadius = 2
        dots.maximumPointScreenSpaceRadius = 4

        let geometry = SCNGeometry(sources: [positions, colors], elements: [dots])
        let material = SCNMaterial()
        material.lightingModel = .constant
        geometry.materials = [material]
        return geometry
    }
}
