//
//  RoomScanView.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 11/11/26.
//
//  The camera, with each tapped item's outline. The floor is not drawn (A10-112: it is found without a tap, and the
//  grid cost memory on the main thread).
//  A10-106: RealityKit's ARView (it was SceneKit's ARSCNView), so the 3D outline can hide behind real surfaces.
//  Apple's coaching screen (as in Measure) sits on it while tracking starts or is lost.
//

import Foundation
import ARKit
import MeasureKit
import RealityKit
import SwiftUI

struct RoomScanView: UIViewRepresentable {
    let session: ARSession
    /// A10-106: the world box of each tapped item, drawn as a 3D dashed box.
    var outlines: [UUID: WorldBox] = [:]
    /// Apple's coaching screen showed (true) or went (false); the scan's own instruction steps aside meanwhile.
    var onCoachingChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = Self.makeCameraView(session: session)
        let root = AnchorEntity(world: .zero)
        view.scene.addAnchor(root)
        context.coordinator.root = root
        context.coordinator.outlines = ScanOutlines(root: root)
        view.subviews.compactMap { $0 as? ARCoachingOverlayView }.first?.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.onCoachingChange = onCoachingChange
        context.coordinator.outlines?.show(outlines, cameraPosition: view.cameraTransform.translation,
                                           focalLength: Self.focalLength(of: view))
    }

    /// The camera view on the scan's own session. ScanSession configures and runs it and stays its delegate, so the
    /// view must not configure the session itself.
    static func makeCameraView(session: ARSession) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = session
        // A10-106: the room mesh hides the parts of the outline that are behind real surfaces.
        view.environment.sceneUnderstanding.options.insert(.occlusion)
        // A10-106 crash fix: no grounding shadows; the lines and grid need none, and they cost GPU work.
        view.renderOptions.insert(.disableGroundingShadows)
        view.addSubview(makeCoachingView(session: session, in: view.bounds))
        return view
    }

    /// Apple's coaching screen, as in Measure: the camera dims and an animation asks to move the iPhone, while
    /// tracking starts, while looking for a surface, and whenever tracking is lost. ARKit shows and hides it.
    static func makeCoachingView(session: ARSession, in bounds: CGRect) -> ARCoachingOverlayView {
        let coaching = ARCoachingOverlayView(frame: bounds)
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coaching.session = session
        coaching.goal = .horizontalPlane
        coaching.activatesAutomatically = true
        return coaching
    }

    /// The camera's focal length in screen points: the picture's fx (pixels), scaled the way the upright picture fills
    /// the view (as `ScanOverlay`). Zero before the first frame.
    static func focalLength(of view: ARView) -> Float {
        guard let camera = view.session.currentFrame?.camera, view.bounds.width > 0 else { return 0 }
        let picture = camera.imageResolution
        let scale = max(view.bounds.width / picture.height, view.bounds.height / picture.width)
        return camera.intrinsics[0][0] * Float(scale)
    }

    final class Coordinator: NSObject, ARCoachingOverlayViewDelegate {
        var root: AnchorEntity?
        var outlines: ScanOutlines?
        var onCoachingChange: (Bool) -> Void = { _ in }

        func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
            onCoachingChange(true)
        }

        func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
            onCoachingChange(false)
        }
    }
}
