//
//  ScanOutlines.swift
//  Skema Photo
//
//  A10-106 (Amadeus, 21 Nov): each tapped item's world box drawn as a true 3D box in the camera view. White, 70%,
//  dashed (6 cm dash, 4 cm gap), round ends, 4 pt on the screen at every distance. The room mesh hides the parts
//  behind real surfaces (RealityKit occlusion, turned on in RoomScanView).
//

import Foundation
import MeasureKit
import RealityKit
import UIKit

@MainActor
final class ScanOutlines {
    /// One dash: a rod with a ball at each end, so its ends are round.
    private struct Dash {
        let rod: ModelEntity
        let caps: [ModelEntity]
        let middle: SIMD3<Float>
        let length: Float
    }

    private struct Outline {
        let box: WorldBox
        let entity: Entity
        let dashes: [Dash]
    }

    /// A box that moved less than this (1 cm on every side) keeps its old dashes, so they are not rebuilt 5 times a
    /// second while the grown box changes by millimetres.
    static let rebuildStep: Float = 0.01

    private let root: Entity
    private var outlines: [UUID: Outline] = [:]

    private static let rodMesh = MeshResource.generateCylinder(height: 1, radius: 1)
    private static let capMesh = MeshResource.generateSphere(radius: 1)
    private static let material: UnlitMaterial = {
        var material = UnlitMaterial(color: .white)
        material.blending = .transparent(opacity: .init(floatLiteral: OutlineLayout.opacity))
        return material
    }()

    init(root: Entity) {
        self.root = root
    }

    /// Shows exactly the given boxes: new ones are built, changed ones rebuilt, missing ones removed.
    func show(_ boxes: [UUID: WorldBox]) {
        for (id, outline) in outlines where boxes[id] == nil {
            outline.entity.removeFromParent()
            outlines[id] = nil
        }
        for (id, box) in boxes {
            if let old = outlines[id], !Self.hasMoved(from: old.box, to: box) { continue }
            outlines[id]?.entity.removeFromParent()
            let outline = Self.makeOutline(of: box)
            root.addChild(outline.entity)
            outlines[id] = outline
        }
    }

    /// Every frame: each dash gets the radius that makes it `OutlineLayout.thickness` points thick at its distance.
    func resize(cameraPosition: SIMD3<Float>, focalLength: Float) {
        guard focalLength > 0 else { return }
        for outline in outlines.values {
            for dash in outline.dashes {
                let radius = OutlineLayout.radius(distance: simd_distance(cameraPosition, dash.middle),
                                                  focalLength: focalLength)
                dash.rod.scale = SIMD3(radius, dash.length, radius)
                for cap in dash.caps { cap.scale = SIMD3(repeating: radius) }
            }
        }
    }

    private static func hasMoved(from old: WorldBox, to new: WorldBox) -> Bool {
        simd_reduce_max(simd_abs(old.min - new.min)) >= rebuildStep
            || simd_reduce_max(simd_abs(old.max - new.max)) >= rebuildStep
    }

    private static func makeOutline(of box: WorldBox) -> Outline {
        let entity = Entity()
        var dashes: [Dash] = []
        for edge in box.edges {
            for piece in OutlineLayout.dashes(from: edge.start, to: edge.end) {
                let dash = makeDash(from: piece.start, to: piece.end)
                entity.addChild(dash.rod)
                dash.caps.forEach { entity.addChild($0) }
                dashes.append(dash)
            }
        }
        return Outline(box: box, entity: entity, dashes: dashes)
    }

    /// A rod from `start` to `end` (the cylinder's axis is y, turned onto the dash) and a ball at each end.
    /// Box edges always run along +x, +y or +z, so the turn is never a half turn.
    private static func makeDash(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Dash {
        let length = simd_distance(start, end)
        let rod = ModelEntity(mesh: rodMesh, materials: [material])
        rod.position = (start + end) / 2
        rod.orientation = simd_quatf(from: SIMD3(0, 1, 0), to: (end - start) / length)
        let caps = [start, end].map { point -> ModelEntity in
            let cap = ModelEntity(mesh: capMesh, materials: [material])
            cap.position = point
            return cap
        }
        return Dash(rod: rod, caps: caps, middle: (start + end) / 2, length: length)
    }
}
