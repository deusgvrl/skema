//
//  MetalScanView.swift
//  Final Challenge App
//
//  Created by Amadeus Gavriel on 24/11/26.
//
//  The scan screen's camera with the own Metal renderer (Metal renderer, part 2). It has the same inputs as
//  RoomScanView, so the screen can choose between them.
//

import ARKit
import MeasureKit
import MetalKit
import os
import SwiftUI

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Skema", category: "MetalScan")

struct MetalScanView: UIViewRepresentable {
    let session: ARSession
    /// The world box of each tapped item, drawn as a 3D dashed box.
    var outlines: [UUID: WorldBox] = [:]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        guard let view = Self.makeMetalView(session: session) else {
            // No Metal device or no renderer: an empty view keeps the screen alive (the renderer choice should not pick
            // Metal then).
            log.error("Metal scan view: Metal setup failed, showing an empty view")
            return MTKView()
        }
        context.coordinator.renderer = view.renderer
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.renderer?.outlines = outlines
    }

    /// The view the renderer draws into, or nil when there is no Metal device or the renderer cannot be made. The
    /// formats match the renderer's pipelines. No depth buffer: the outline pass does its own depth test (LiDAR).
    static func makeMetalView(session: ARSession) -> ScanMTKView? {
        guard let device = MTLCreateSystemDefaultDevice() else {
            log.error("Metal scan view: no Metal device")
            return nil
        }
        guard let renderer = ScanMetalRenderer(device: device, session: session) else { return nil }
        let view = ScanMTKView(frame: .zero, device: device)
        view.colorPixelFormat = ScanMetalRenderer.colorPixelFormat
        view.depthStencilPixelFormat = .invalid
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.renderer = renderer
        view.delegate = renderer
        return view
    }

    /// What the coaching view helps to find. The scan needs a floor (a horizontal plane).
    static let coachingGoal: ARCoachingOverlayView.Goal = .horizontalPlane

    /// The coaching view on the scan's session: it asks the person to find a flat surface when tracking needs it.
    /// The settings are the same as the scan-instruction branch.
    static func makeCoachingView(session: ARSession, in bounds: CGRect) -> ARCoachingOverlayView {
        let view = ARCoachingOverlayView(frame: bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.session = session
        view.goal = coachingGoal
        view.activatesAutomatically = true
        return view
    }

    final class Coordinator {
        var renderer: ScanMetalRenderer?
    }
}

/// An MTKView that owns its renderer. `MTKView.delegate` is weak, so something must keep the renderer alive.
final class ScanMTKView: MTKView {
    var renderer: ScanMetalRenderer?
}
