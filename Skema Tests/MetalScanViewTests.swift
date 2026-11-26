//
//  MetalScanViewTests.swift
//  Skema Tests
//
//  Created by Amadeus Gavriel on 24/11/26.
//
//  The Metal scan view: its coaching view has the same settings as the scan-instruction branch (R7), its layer is
//  set up for the renderer (R12), and its display link and render thread follow the window (R13). The Metal view
//  tests are skipped when this machine has no Metal device.
//

import ARKit
import Foundation
import Metal
import QuartzCore
import Testing
import UIKit
@testable import Skema_Photo

@MainActor
@Suite("Metal scan view")
struct MetalScanViewTests {
    @Test("R7: the coaching view has the session, the horizontal plane goal and activates by itself")
    func coachingViewSettings() {
        let session = ARSession()
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)

        let view = MetalScanView.makeCoachingView(session: session, in: bounds)

        #expect(MetalScanView.coachingGoal == .horizontalPlane)
        // The simulator's ARCoachingOverlayView does not keep `session` and `goal` (they read back nil and 0), so
        // these two are checked on a device only.
        #if !targetEnvironment(simulator)
        #expect(view.session === session)
        #expect(view.goal == .horizontalPlane)
        #endif
        #expect(view.activatesAutomatically)
        #expect(view.frame == bounds)
        #expect(view.autoresizingMask == [.flexibleWidth, .flexibleHeight])
    }

    @Test("R12: the view's layer is a CAMetalLayer with the renderer's colour format, frame-buffer-only, and a device",
          .enabled(if: MTLCreateSystemDefaultDevice() != nil,
                    "No Metal device here: the Metal view tests are skipped."))
    func metalLayerSettings() throws {
        let view = try #require(MetalScanView.makeMetalView(session: ARSession()))

        let layer = try #require(view.layer as? CAMetalLayer)
        #expect(layer.pixelFormat == .bgra8Unorm)
        #expect(layer.pixelFormat == ScanMetalRenderer.colorPixelFormat)
        #expect(layer.framebufferOnly)
        #expect(layer.device != nil)
    }

    @Test("R12: layout sets the drawable size to the bounds times the scale, and the size in points for the renderer",
          .enabled(if: MTLCreateSystemDefaultDevice() != nil,
                    "No Metal device here: the Metal view tests are skipped."))
    func layoutSetsTheSizes() throws {
        let view = try #require(MetalScanView.makeMetalView(session: ARSession()))

        view.contentScaleFactor = 3
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        view.layoutIfNeeded()

        let layer = try #require(view.layer as? CAMetalLayer)
        #expect(layer.drawableSize == CGSize(width: 1170, height: 2532))
        #expect(view.inbox.snapshot().viewSize == CGSize(width: 390, height: 844))
    }

    @Test("R13: in a window, the display link asks for 60 fps and the render thread runs; out of it, both stop",
          .enabled(if: MTLCreateSystemDefaultDevice() != nil,
                    "No Metal device here: the Metal view tests are skipped."))
    func displayLinkAndThreadFollowTheWindow() throws {
        let view = try #require(MetalScanView.makeMetalView(session: ARSession()))
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
                                 "No window scene in the test host")
        let window = UIWindow(windowScene: scene)
        window.addSubview(view)
        defer { view.removeFromSuperview() }

        let thread = try #require(view.renderThread, "No render thread in a window")
        // The test keeps no strong reference to the link, so a weak one shows whether the link was let go.
        weak var weakLink: CAMetalDisplayLink?
        do {
            let link = try #require(view.displayLink, "No display link in a window")
            weakLink = link
            #expect(link.preferredFrameRateRange.minimum == 60)
            #expect(link.preferredFrameRateRange.maximum == 60)
            #expect(link.preferredFrameRateRange.preferred == 60)
        }
        #expect(!thread.isFinished)

        view.removeFromSuperview()

        #expect(view.displayLink == nil)
        #expect(waitUntil(timeout: 1) { thread.isFinished }, "The render thread did not end within 1 second")
        // The run loop keeps a link that is not invalidated, so a nil here means invalidate() ran.
        #expect(waitUntil(timeout: 1) { weakLink == nil }, "The display link was not invalidated")
    }

    @Test("R13b: a drawing handle that is freed stops its thread and invalidates its link",
          .enabled(if: MTLCreateSystemDefaultDevice() != nil,
                    "No Metal device here: the Metal view tests are skipped."))
    func freedHandleStopsItsThread() throws {
        // A view that is freed in a window is also taken out of it by UIKit, which stops the drawing, so the safety
        // net is tested on the handle itself.
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(ScanMetalRenderer(device: device, session: ARSession(), inbox: OutlineInbox()))
        var thread: RenderThread?
        weak var weakLink: CAMetalDisplayLink?
        autoreleasepool {
            let handle = DrawingHandle(metalLayer: CAMetalLayer(), renderer: renderer)
            thread = handle.thread
            weakLink = handle.link
        }
        let started = try #require(thread)

        #expect(waitUntil(timeout: 1) { started.isFinished }, "The render thread did not end within 1 second")
        #expect(waitUntil(timeout: 1) { weakLink == nil }, "The display link was not invalidated")
    }

    @Test("R12b: a view laid out before it joins a window gets the window's native scale",
          .enabled(if: MTLCreateSystemDefaultDevice() != nil,
                    "No Metal device here: the Metal view tests are skipped."))
    func joiningAWindowSetsTheDrawableSize() throws {
        let view = try #require(MetalScanView.makeMetalView(session: ARSession()))
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
                                 "No window scene in the test host")
        let window = UIWindow(windowScene: scene)
        let nativeScale = window.screen.nativeScale
        try #require(nativeScale > 1, "This test needs a screen with a native scale above 1")
        defer { view.removeFromSuperview() }

        // Out of a window the layer can have a scale of 1, and layout may not run again later.
        view.contentScaleFactor = 1
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        view.layoutIfNeeded()
        window.addSubview(view)

        let layer = try #require(view.layer as? CAMetalLayer)
        #expect(layer.drawableSize == CGSize(width: 390 * nativeScale, height: 844 * nativeScale))
        #expect(view.inbox.snapshot().viewSize == CGSize(width: 390, height: 844))
    }
}
