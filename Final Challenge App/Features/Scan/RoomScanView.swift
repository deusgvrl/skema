//
//  RoomScanView.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 11/11/26.
//
//  The camera, with a green grid lying on the floor once it is tapped (Sketch UT Review T02).
//  A10-106: RealityKit's ARView (it was SceneKit's ARSCNView), so the 3D outline can hide behind real surfaces.
//

import Foundation
import ARKit
import RealityKit
import SwiftUI

struct RoomScanView: UIViewRepresentable {
    let session: ARSession
    /// A world point on the floor (the floor tap at the floor's height); nil hides the grid.
    var floor: SIMD3<Float>?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = Self.makeCameraView(session: session)
        let root = AnchorEntity(world: .zero)
        view.scene.addAnchor(root)
        context.coordinator.root = root
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        guard let floor else {
            context.coordinator.grid?.removeFromParent()
            context.coordinator.grid = nil
            return
        }
        let grid = context.coordinator.grid ?? FloorGrid.makeEntity()
        if grid.parent == nil { context.coordinator.root?.addChild(grid) }
        context.coordinator.grid = grid
        // A few millimetres up, so the grid never sinks under the real floor.
        grid.position = SIMD3(floor.x, floor.y + 0.005, floor.z)
    }

    /// The camera view on the scan's own session. ScanSession configures and runs it and stays its delegate, so the
    /// view must not configure the session itself.
    static func makeCameraView(session: ARSession) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = session
        return view
    }

    final class Coordinator {
        var root: AnchorEntity?
        var grid: ModelEntity?
    }
}

/// A 4 m green grid, 25 cm squares, fading out towards its edge.
enum FloorGrid {
    static let size: Float = 4
    static let squares = 16

    /// The same grid as the SceneKit version: flat on the floor, unlit, seen from both sides, writes no depth.
    static func makeEntity() -> ModelEntity {
        var material = UnlitMaterial()
        if let image = texture().cgImage,
           let texture = try? TextureResource(image: image, options: .init(semantic: .color)) {
            material.color = .init(tint: .white, texture: .init(texture))
        }
        material.blending = .transparent(opacity: 1.0)
        material.faceCulling = .none
        material.writesDepth = false
        return ModelEntity(mesh: .generatePlane(width: size, depth: size), materials: [material])
    }

    private static func texture() -> UIImage {
        let side: CGFloat = 512
        let green = UIColor(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255, alpha: 1)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let graphics = context.cgContext
            graphics.setFillColor(green.withAlphaComponent(0.12).cgColor)
            graphics.fill(CGRect(x: 0, y: 0, width: side, height: side))
            graphics.setStrokeColor(green.withAlphaComponent(0.8).cgColor)
            graphics.setLineWidth(2)
            let step = side / CGFloat(squares)
            for index in 0...squares {
                let offset = CGFloat(index) * step
                graphics.move(to: CGPoint(x: offset, y: 0))
                graphics.addLine(to: CGPoint(x: offset, y: side))
                graphics.move(to: CGPoint(x: 0, y: offset))
                graphics.addLine(to: CGPoint(x: side, y: offset))
            }
            graphics.strokePath()
            // Fade towards the edge: keep the middle, clear the corners.
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            if let fade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.3, 1]) {
                graphics.setBlendMode(.destinationIn)
                let centre = CGPoint(x: side / 2, y: side / 2)
                graphics.drawRadialGradient(fade, startCenter: centre, startRadius: 0,
                                            endCenter: centre, endRadius: side / 2, options: [])
            }
        }
    }
}
