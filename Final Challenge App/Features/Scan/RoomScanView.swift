//
//  RoomScanView.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 11/11/26.
//
//  The camera, with a green grid lying on the floor once it is tapped (Sketch UT Review T02).
//

import Foundation
import ARKit
import SwiftUI

struct RoomScanView: UIViewRepresentable {
    let session: ARSession
    /// A world point on the floor (the floor tap at the floor's height); nil hides the grid.
    var floor: SIMD3<Float>?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.automaticallyUpdatesLighting = false
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {
        guard let floor else {
            context.coordinator.grid?.removeFromParentNode()
            context.coordinator.grid = nil
            return
        }
        let grid = context.coordinator.grid ?? FloorGrid.makeNode()
        if grid.parent == nil { view.scene.rootNode.addChildNode(grid) }
        context.coordinator.grid = grid
        // A few millimetres up, so the grid never sinks under the real floor.
        grid.simdPosition = SIMD3(floor.x, floor.y + 0.005, floor.z)
    }

    final class Coordinator {
        var grid: SCNNode?
    }
}

/// A 4 m green grid, 25 cm squares, fading out towards its edge.
enum FloorGrid {
    static let size: CGFloat = 4
    static let squares = 16

    static func makeNode() -> SCNNode {
        let plane = SCNPlane(width: size, height: size)
        let material = SCNMaterial()
        material.diffuse.contents = texture()
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2
        return node
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
