//
//  ScanOutlines.swift
//  Skema Photo
//
//  A10-106 (Amadeus, 21 Nov): each tapped item's world box drawn as a true 3D box in the camera view. White, 70%,
//  dashed (6 cm dash, 4 cm gap), round ends. The room mesh hides the parts behind real surfaces (RealityKit
//  occlusion, turned on in RoomScanView).
//  Crash fix (21 Nov): each box is ONE mesh and one entity (it was about 1,500 entities, which ran the GPU out of
//  memory). The line thickness is set when the mesh is built (T1): 4 pt at the camera's distance at that moment.
//

import Foundation
import MeasureKit
import RealityKit
import UIKit

@MainActor
final class ScanOutlines {
    private struct Outline {
        let box: WorldBox
        let entity: ModelEntity
    }

    /// A box that moved less than this (1 cm on every side) keeps its old mesh.
    static let rebuildStep: Float = 0.01

    private let root: Entity
    private var outlines: [UUID: Outline] = [:]

    private static let material: UnlitMaterial = {
        var material = UnlitMaterial(color: .white)
        material.blending = .transparent(opacity: .init(floatLiteral: OutlineLayout.opacity))
        material.faceCulling = .none
        return material
    }()

    init(root: Entity) {
        self.root = root
    }

    /// Shows exactly the given boxes: new ones are built, moved ones get a new mesh, missing ones are removed.
    /// `focalLength` is in screen points; before the first camera frame it is 0 and nothing is built yet.
    func show(_ boxes: [UUID: WorldBox], cameraPosition: SIMD3<Float>, focalLength: Float) {
        for (id, outline) in outlines where boxes[id] == nil {
            outline.entity.removeFromParent()
            outlines[id] = nil
        }
        guard focalLength > 0 else { return }
        for (id, box) in boxes {
            if let old = outlines[id], !Self.hasMoved(from: old.box, to: box) { continue }
            let radius = OutlineMesh.radius(for: box, cameraPosition: cameraPosition, focalLength: focalLength)
            guard let mesh = Self.mesh(of: OutlineMesh.geometry(of: box, radius: radius)) else { continue }
            if let old = outlines[id] {
                old.entity.model?.mesh = mesh
                outlines[id] = Outline(box: box, entity: old.entity)
            } else {
                let entity = ModelEntity(mesh: mesh, materials: [Self.material])
                root.addChild(entity)
                outlines[id] = Outline(box: box, entity: entity)
            }
        }
    }

    private static func hasMoved(from old: WorldBox, to new: WorldBox) -> Bool {
        simd_reduce_max(simd_abs(old.min - new.min)) >= rebuildStep
            || simd_reduce_max(simd_abs(old.max - new.max)) >= rebuildStep
    }

    /// One RealityKit mesh from the box's triangles. Nil when there are none or RealityKit refuses them.
    private static func mesh(of geometry: OutlineGeometry) -> MeshResource? {
        guard !geometry.indices.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: "outline")
        descriptor.positions = MeshBuffers.Positions(geometry.positions)
        descriptor.primitives = .triangles(geometry.indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
