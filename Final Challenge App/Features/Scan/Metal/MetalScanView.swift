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
import Metal
import os
import QuartzCore
import SwiftUI
import UIKit

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Skema", category: "MetalScan")

struct MetalScanView: UIViewRepresentable {
    let session: ARSession
    /// The world box of each tapped item, drawn as a 3D dashed box.
    var outlines: [UUID: WorldBox] = [:]

    func makeUIView(context: Context) -> UIView {
        guard let view = Self.makeMetalView(session: session) else {
            // No Metal device or no renderer: an empty view keeps the screen alive (the renderer choice should not pick
            // Metal then).
            log.error("Metal scan view: Metal setup failed, showing an empty view")
            return UIView()
        }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        // The render thread reads them at the start of its next frame.
        (view as? ScanMetalLayerView)?.inbox.setOutlines(outlines)
    }

    /// The view the renderer draws into, or nil when there is no Metal device or the renderer cannot be made. The
    /// format matches the renderer's pipelines. No depth buffer: the outline pass does its own depth test (LiDAR).
    static func makeMetalView(session: ARSession) -> ScanMetalLayerView? {
        guard let device = MTLCreateSystemDefaultDevice() else {
            log.error("Metal scan view: no Metal device")
            return nil
        }
        let inbox = OutlineInbox()
        guard let renderer = ScanMetalRenderer(device: device, session: session, inbox: inbox) else { return nil }
        return ScanMetalLayerView(device: device, renderer: renderer)
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
}

/// A view whose layer is a `CAMetalLayer`. In a window it draws on its own render thread: a `CAMetalDisplayLink` on
/// that thread's run loop calls the renderer once per frame. Out of the window, the link and the thread stop (so
/// Finish, which removes the view, also stops the drawing).
final class ScanMetalLayerView: UIView {
    // UIView's `layerClass` is a class property: it cannot be `static` in an override.
    // swiftlint:disable:next static_over_final_class
    override class var layerClass: AnyClass { CAMetalLayer.self }

    /// The newest outlines and the view size, for the renderer.
    let inbox: OutlineInbox
    /// `CAMetalDisplayLink.delegate` is weak, so this view keeps the renderer alive.
    private let renderer: ScanMetalRenderer
    private var drawing: DrawingHandle?

    /// The render thread, while the view is in a window.
    var renderThread: RenderThread? { drawing?.thread }
    /// The display link, while the view is in a window.
    var displayLink: CAMetalDisplayLink? { drawing?.link }

    private var metalLayer: CAMetalLayer {
        // layerClass is CAMetalLayer, so this cannot fail.
        // swiftlint:disable:next force_cast
        layer as! CAMetalLayer
    }

    init(device: any MTLDevice, renderer: ScanMetalRenderer) {
        self.renderer = renderer
        self.inbox = renderer.inbox
        super.init(frame: .zero)
        metalLayer.device = device
        metalLayer.pixelFormat = ScanMetalRenderer.colorPixelFormat
        metalLayer.framebufferOnly = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateSizes()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopDrawing()
        } else {
            // Before the view joins a window its scale can be 1, and layout need not run again.
            updateSizes()
            if drawing == nil { startDrawing() }
        }
    }

    /// The drawable is in pixels: the bounds times the screen's native scale. With no window, the view's own scale.
    private func updateSizes() {
        let scale = window?.screen.nativeScale ?? contentScaleFactor
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        inbox.setViewSize(bounds.size)
    }

    private func startDrawing() {
        drawing = DrawingHandle(metalLayer: metalLayer, renderer: renderer)
    }

    /// Frees the handle: its `deinit` invalidates the link and stops the thread.
    private func stopDrawing() {
        drawing = nil
    }
}

/// The render thread and the display link of one drawing session, in one `Sendable` value.
nonisolated final class DrawingHandle: Sendable {
    let thread: RenderThread
    private let linkBox: UncheckedSendable<CAMetalDisplayLink>
    private let rendererBox: UncheckedSendable<ScanMetalRenderer>

    var link: CAMetalDisplayLink { linkBox.value }

    /// Starts the thread, makes the link for `metalLayer` and adds it to the thread's run loop.
    @MainActor
    init(metalLayer: CAMetalLayer, renderer: ScanMetalRenderer) {
        let thread = RenderThread()
        thread.start()
        let link = CAMetalDisplayLink(metalLayer: metalLayer)
        // `CAMetalDisplayLink.delegate` is weak: the handle keeps the renderer alive.
        link.delegate = renderer
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        // The link joins the render thread's run loop from that thread.
        let onThread = UncheckedSendable(link)
        thread.perform { onThread.value.add(to: .current, forMode: .default) }
        self.thread = thread
        self.linkBox = onThread
        self.rendererBox = UncheckedSendable(renderer)
    }

    /// The safety net: a handle that is freed, even without a call from the view, stops the link and the thread.
    deinit { stop() }

    /// Invalidates the link on the render thread and ends the thread.
    private func stop() {
        let link = linkBox
        // The block owns the renderer, so the last release of it is on the render thread, after `invalidate()`: the
        // renderer's Metal objects are then freed on the thread that used them. (No test: a release on the wrong
        // thread leaves no visible trace.)
        let renderer = rendererBox
        thread.perform { withExtendedLifetime(renderer) { link.value.invalidate() } }
        thread.stop()
    }
}

/// Moves a non-Sendable object to the render thread. Safe here: after the hand-over the object is used on the render
/// thread only for `add(to:)` and `invalidate()`. The main thread only reads the link's settings (for example
/// `preferredFrameRateRange`) and does not call `add` or `invalidate` again.
nonisolated struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
