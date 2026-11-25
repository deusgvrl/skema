//
//  MetalScanViewTests.swift
//  Skema Tests
//
//  Created by Amadeus Gavriel on 24/11/26.
//
//  The Metal scan view (R7): its MTKView is set up for the renderer, and its coaching view has the same settings
//  as the scan-instruction branch. The MTKView tests are skipped when this machine has no Metal device.
//

import ARKit
import Foundation
import MetalKit
import Testing
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

    @Test("R7: the Metal view has a ScanMetalRenderer as delegate and draws 60 frames a second",
          .enabled(if: MTLCreateSystemDefaultDevice() != nil,
                    "No Metal device here: the Metal view tests are skipped."))
    func metalViewHasRendererAndSixtyFPS() throws {
        let view = try #require(MetalScanView.makeMetalView(session: ARSession()))

        #expect(view.delegate is ScanMetalRenderer)
        #expect(view.preferredFramesPerSecond == 60)
    }

    @Test("R7: the Metal view uses the renderer's colour format, no depth buffer and a frame-buffer-only drawable",
          .enabled(if: MTLCreateSystemDefaultDevice() != nil,
                    "No Metal device here: the Metal view tests are skipped."))
    func metalViewFormats() throws {
        let view = try #require(MetalScanView.makeMetalView(session: ARSession()))

        #expect(view.device != nil)
        #expect(view.colorPixelFormat == .bgra8Unorm)
        #expect(view.colorPixelFormat == ScanMetalRenderer.colorPixelFormat)
        #expect(view.depthStencilPixelFormat == .invalid)
        #expect(view.framebufferOnly)
    }
}
