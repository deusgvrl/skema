//
//  UsedPointsEntities.swift
//  Skema Photo
//
//  The "Centres" debug view as 3D objects in the camera view (RealityKit; it was SceneKit nodes before A10-106): per
//  item a dot at its top centre (in the item's colour), a white dot at its base centre on the floor, and a line between
//  them. Drawn over everything, so the room mesh's occlusion does not hide them.
//

import Foundation
import RealityKit
import UIKit

@MainActor
final class UsedPointsEntities {
    /// The centre dots' radius (1.5 cm).
    static let dotRadius: Float = 0.015
    /// The line from the top centre to the base centre is this thick (4 mm).
    static let lineThickness: Float = 0.004

    private let container = Entity()
    private var drawn: [UUID: UsedPoints] = [:]

    init(root: Entity) {
        root.addChild(container)
    }

    /// Creates, rebuilds and removes the groups so they match `items`; a group that did not change is left alone.
    func show(_ items: [UsedPoints]) {
        let listed = Set(items.map(\.id))
        for id in drawn.keys where !listed.contains(id) {
            container.findEntity(named: id.uuidString)?.removeFromParent()
            drawn[id] = nil
        }
        for item in items where drawn[item.id] != item {
            container.findEntity(named: item.id.uuidString)?.removeFromParent()
            container.addChild(Self.group(for: item))
            drawn[item.id] = item
        }
    }

    private static func group(for item: UsedPoints) -> Entity {
        let group = Entity()
        group.name = item.id.uuidString
        let color = UIColor(red: CGFloat(item.color.x), green: CGFloat(item.color.y), blue: CGFloat(item.color.z),
                            alpha: 1)
        group.addChild(dot(at: item.topCentre, color: color))
        group.addChild(dot(at: item.baseCentre, color: .white))
        if let line = line(from: item.topCentre, to: item.baseCentre) { group.addChild(line) }
        return group
    }

    private static func dot(at position: SIMD3<Float>, color: UIColor) -> ModelEntity {
        let dot = ModelEntity(mesh: .generateSphere(radius: dotRadius), materials: [material(color)])
        dot.position = position
        return dot
    }

    /// A thin box from `top` to `base`; nothing when they are the same point.
    private static func line(from top: SIMD3<Float>, to base: SIMD3<Float>) -> ModelEntity? {
        let length = simd_distance(top, base)
        guard length > 1e-4 else { return nil }
        let mesh = MeshResource.generateBox(width: lineThickness, height: length, depth: lineThickness)
        let line = ModelEntity(mesh: mesh, materials: [material(.white)])
        line.position = (top + base) / 2
        line.orientation = simd_quatf(from: SIMD3(0, 1, 0), to: (top - base) / length)
        return line
    }

    /// Flat colour, not shaded, and drawn over the camera picture and the room mesh.
    private static func material(_ color: UIColor) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.faceCulling = .none
        material.readsDepth = false
        return material
    }
}
