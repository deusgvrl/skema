//
//  ScanMetalRendererTests.swift
//  Skema Tests
//
//  Created by Amadeus Gavriel on 24/11/26.
//
//  The Metal renderer: its uniforms for one frame (R4), that its shaders and pipelines build, and that its outline
//  pass really hides a box behind a nearer LiDAR depth; a box off the screen loses its buffers and gets them back
//  (O6–O7, A10-121). Shared camera: fx = fy = 1500, centre (960, 720),
//  1920 x 1440 picture, no turn or move, shown on a 390 x 844 portrait view.
//

import ARKit
import Foundation
import MeasureKit
import Metal
import simd
import Testing
@testable import Skema_Photo

private let viewSize = CGSize(width: 390, height: 844)

private func sharedCamera() -> CameraModel {
    var intrinsics = matrix_identity_float3x3
    intrinsics[0][0] = 1500
    intrinsics[1][1] = 1500
    intrinsics[2][0] = 960
    intrinsics[2][1] = 720
    return CameraModel(intrinsics: intrinsics, imageResolution: SIMD2(1920, 1440),
                       cameraToWorld: matrix_identity_float4x4)
}

@MainActor
@Suite(
    "Scan Metal renderer",
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "No Metal device here: the renderer tests are skipped.")
)
struct ScanMetalRendererTests {
    @Test("R4: the uniforms use ScanProjection, the OcclusionRule numbers and the picture size",
          arguments: [true, false])
    func uniformsForTheSharedCamera(hasDepth: Bool) {
        let camera = sharedCamera()

        let uniforms = ScanMetalRenderer.uniforms(camera: camera, viewSize: viewSize, hasDepth: hasDepth)

        #expect(uniforms.viewProjection == ScanProjection.viewProjection(camera: camera, viewSize: viewSize))
        let corners = [uniforms.quadTexCoords.0, uniforms.quadTexCoords.1,
                       uniforms.quadTexCoords.2, uniforms.quadTexCoords.3]
        #expect(corners == ScanProjection.pictureQuadTexCoords(camera: camera, viewSize: viewSize))
        #expect(uniforms.occlusionMargin == 0.03)
        #expect(uniforms.occlusionMargin == OcclusionRule.margin)
        #expect(uniforms.minConfidence == 1)
        #expect(uniforms.minConfidence == UInt32(OcclusionRule.minConfidence))
        #expect(uniforms.maxRange == 5)
        #expect(uniforms.maxRange == OcclusionRule.maxRange)
        #expect(uniforms.pictureSize == SIMD2(1920, 1440))
        #expect(uniforms.hasDepth == (hasDepth ? 1 : 0))
        #expect(uniforms.lineColor == SIMD4(0.188, 0.820, 0.345, OutlineLayout.opacity))
    }

    @Test("The shaders compile and the pipelines build on this device")
    func initBuildsThePipelines() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())

        #expect(ScanMetalRenderer(device: device, session: ARSession()) != nil)
    }

    @Test("The outline pass hides a box behind nearer LiDAR depth and shows it in front of farther depth")
    func outlinePassUsesTheDepth() throws {
        // A 40 cm box 2 m in front of the camera (line depths 1.8 to 2.2 m).
        let inFront = try linePixelCount(sceneDepth: 1.0)
        let behind = try linePixelCount(sceneDepth: 3.0)

        #expect(inFront == 0, "Scene depth 1 m is in front of the box: no line pixel may show")
        #expect(behind > 0, "Scene depth 3 m is behind the box: the lines must show")
    }

    @Test("R11: encode on the render thread draws the same pixels as on the main thread")
    func encodeOnTheRenderThreadDrawsTheSamePixels() throws {
        let onMain = try renderOutline(sceneDepth: 3.0)
        let onRenderThread = try renderOutline(sceneDepth: 3.0, onRenderThread: true)

        try #require(onMain.linePixels > 0, "The main-thread picture has no line: nothing to compare")
        #expect(onRenderThread.pixels == onMain.pixels)
    }

    @Test("A line is drawn once: the back face of a tube is culled, so no pixel gets two layers of green")
    func outlineIsOneLayerOfGreen() throws {
        let result = try renderOutline(sceneDepth: 3.0)

        // One layer: the line's green (0.820) at OutlineLayout.opacity over black is 0.820 x 0.7 x 255 = about 146.
        // Two layers would be about 190. The brightest pixel is not used: where two different arms cross on the screen,
        // two layers are right. The most common line value is one tube's own layer.
        let oneLayer = Int((Self.lineGreen * OutlineLayout.opacity * 255).rounded())
        #expect(abs(result.commonGreen - oneLayer) <= 12,
                "Most common line value \(result.commonGreen), one layer \(oneLayer). Histogram: \(result.histogram)")
    }

    @Test("A box still being scanned is drawn white; once its item is done, green (#30D158)", arguments: [false, true])
    func outlineColourFollowsDone(isDone: Bool) throws {
        let result = try renderOutline(sceneDepth: 3.0, isDone: isDone)

        // One layer at OutlineLayout.opacity over black: white gives about 178 in red and green; the green gives
        // about 34 in red and 146 in green.
        let colour: (red: Float, green: Float) = isDone ? (0.188, Self.lineGreen) : (1, 1)
        let red = Int((colour.red * OutlineLayout.opacity * 255).rounded())
        let green = Int((colour.green * OutlineLayout.opacity * 255).rounded())
        #expect(abs(result.commonRed - red) <= 12, "Most common red \(result.commonRed), expected \(red)")
        #expect(abs(result.commonGreen - green) <= 12, "Most common green \(result.commonGreen), expected \(green)")
    }

    @Test("O6: a box off the screen is not drawn and loses its GPU buffers")
    func anOffScreenBoxIsNotDrawnAndLosesItsBuffers() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let buffers = OutlineBuffers(device: device)
        let ahead = UUID()
        let behind = UUID()
        let boxes = [ahead: cube(atZ: -2), behind: cube(atZ: 2)]
        buffers.update(boxes) { _ in 0.005 }
        try #require(buffers.entries[behind] != nil)

        let visible = ScanMetalRenderer.visibleOutlines(boxes, camera: sharedCamera())
        buffers.update(visible) { _ in 0.005 }

        #expect(Set(visible.keys) == [ahead])
        #expect(buffers.entries[ahead] != nil)
        #expect(buffers.entries[behind] == nil)
    }

    @Test("O7: a box back in the view is built again")
    func aBoxBackInViewIsBuiltAgain() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let buffers = OutlineBuffers(device: device)
        let ahead = UUID()
        let behind = UUID()
        let boxes = [ahead: cube(atZ: -2), behind: cube(atZ: 2)]
        let camera = sharedCamera()
        // Both boxes had buffers; looking ahead, the second box loses them.
        buffers.update(boxes) { _ in 0.005 }
        buffers.update(ScanMetalRenderer.visibleOutlines(boxes, camera: camera)) { _ in 0.005 }
        try #require(buffers.entries[behind] == nil)

        // The camera turns half a circle around the up axis: it looks along +z now, so only the second box is ahead.
        let turned = CameraModel(intrinsics: camera.intrinsics, imageResolution: camera.imageResolution,
                                 cameraToWorld: float4x4(simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))))
        let visible = ScanMetalRenderer.visibleOutlines(boxes, camera: turned)
        buffers.update(visible) { _ in 0.005 }

        #expect(Set(visible.keys) == [behind])
        #expect(buffers.entries[behind] != nil)
        #expect(buffers.entries[ahead] == nil)
    }

    /// The green of the outline colour (#30D158, the app's "captured" green), as `ScanMetalRenderer` sets it.
    private static let lineGreen: Float = 0.820

    /// A 20 cm cube on the camera's centre line, `depthZ` metres along the z axis.
    private func cube(atZ depthZ: Float) -> WorldBox {
        WorldBox(min: SIMD3(-0.1, -0.1, depthZ - 0.1), max: SIMD3(0.1, 0.1, depthZ + 0.1))
    }

    /// Draws one box with the renderer's outline pass into a 64 x 128 bgra8Unorm target cleared to black, with a
    /// 1 x 1 depth texture of `sceneDepth` metres and high confidence, and counts the line (green) pixels.
    private func linePixelCount(sceneDepth: Float) throws -> Int {
        try renderOutline(sceneDepth: sceneDepth).linePixels
    }

    private struct OutlineRender {
        let linePixels: Int
        /// The most common non-black green value.
        let commonGreen: Int
        /// The most common red value of the pixels that have some green.
        let commonRed: Int
        let histogram: String
        /// Every byte of the target, to compare two renders exactly.
        let pixels: [UInt8]
    }

    /// The render described at `linePixelCount`, with its line pixel count and its green values.
    /// `onRenderThread`: the encode call runs on a `RenderThread` (the test waits for it). `isDone`: the box's item is
    /// done, so it is drawn green; else white.
    private func renderOutline(sceneDepth: Float, onRenderThread: Bool = false,
                               isDone: Bool = true) throws -> OutlineRender {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(ScanMetalRenderer(device: device, session: ARSession()))
        let id = UUID()
        renderer.outlines = [id: WorldBox(min: SIMD3(-0.2, -0.2, -2.2), max: SIMD3(0.2, 0.2, -1.8))]
        renderer.doneOutlines = isDone ? [id] : []
        let queue = try #require(device.makeCommandQueue())
        let width = 64, height = 128
        let depthBytes = withUnsafeBytes(of: sceneDepth) { Array($0) }
        let depth = try makeTexture(device: device, queue: queue, format: .r32Float, size: (1, 1), bytes: depthBytes)
        let confidence = try makeTexture(device: device, queue: queue, format: .r8Uint, size: (1, 1), bytes: [2])
        let target = try makeTexture(device: device, queue: queue, format: .bgra8Unorm, size: (width, height),
                                     bytes: [UInt8](repeating: 0, count: width * height * 4))
        let readBack = try #require(device.makeBuffer(length: width * height * 4))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        let commands = try #require(queue.makeCommandBuffer())
        let encoder = try #require(commands.makeRenderCommandEncoder(descriptor: pass))
        try encodeOutline(renderer: renderer, encoder: encoder, depth: (depth, confidence),
                          viewSize: CGSize(width: width, height: height), onRenderThread: onRenderThread)
        encoder.endEncoding()
        let blit = try #require(commands.makeBlitCommandEncoder())
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: readBack,
                  destinationOffset: 0, destinationBytesPerRow: width * 4, destinationBytesPerImage: width * height * 4)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        #expect(commands.status == .completed)

        // The line's green at 70% over black is about 146 in the green channel; the background is black.
        let pixels = UnsafeBufferPointer(
            start: readBack.contents().bindMemory(to: UInt8.self, capacity: width * height * 4),
            count: width * height * 4
        )
        let starts = stride(from: 0, to: pixels.count, by: 4)
        // bgra8Unorm: the green channel is byte 1 of each pixel.
        let line = starts.filter { pixels[$0 + 1] >= 100 }.count
        var counts: [Int: Int] = [:]
        for index in starts where pixels[index + 1] > 0 { counts[Int(pixels[index + 1]), default: 0] += 1 }
        let top = counts.sorted { $0.value > $1.value }.prefix(6)
        var reds: [Int: Int] = [:]
        for index in starts where pixels[index + 1] > 0 { reds[Int(pixels[index + 2]), default: 0] += 1 }
        return OutlineRender(linePixels: line, commonGreen: top.first?.key ?? 0,
                             commonRed: reds.max { $0.value < $1.value }?.key ?? 0,
                             histogram: top.map { "\($0.key): \($0.value)" }.joined(separator: ", "),
                             pixels: Array(pixels))
    }

    /// Calls `renderer.encode` for the shared camera, with no camera picture. `onRenderThread`: the call runs on a
    /// `RenderThread` and the test waits for it.
    private func encodeOutline(renderer: ScanMetalRenderer, encoder: any MTLRenderCommandEncoder,
                               depth: (depth: any MTLTexture, confidence: any MTLTexture), viewSize: CGSize,
                               onRenderThread: Bool) throws {
        guard onRenderThread else {
            renderer.encode(into: encoder, camera: sharedCamera(), viewSize: viewSize, picture: nil, sceneDepth: depth)
            return
        }
        let thread = RenderThread()
        thread.start()
        defer { thread.stop() }
        let done = DispatchSemaphore(value: 0)
        let sendable = UncheckedSendable((renderer, encoder, depth.depth, depth.confidence))
        thread.perform {
            let (renderer, encoder, depthTexture, confidence) = sendable.value
            renderer.encode(into: encoder, camera: sharedCamera(), viewSize: viewSize,
                            picture: nil, sceneDepth: (depthTexture, confidence))
            done.signal()
        }
        try #require(done.wait(timeout: .now() + 5) == .success, "The encode did not finish on the render thread")
    }

    /// A private texture filled through a blit (the simulator needs private textures for rendering).
    private func makeTexture(device: any MTLDevice, queue: any MTLCommandQueue, format: MTLPixelFormat,
                             size: (width: Int, height: Int), bytes: [UInt8]) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: size.width, height: size.height, mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .renderTarget]
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let bytesPerRow = bytes.count / size.height
        let source = try #require(device.makeBuffer(bytes: bytes, length: bytes.count))
        let commands = try #require(queue.makeCommandBuffer())
        let blit = try #require(commands.makeBlitCommandEncoder())
        blit.copy(from: source, sourceOffset: 0, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: bytes.count,
                  sourceSize: MTLSize(width: size.width, height: size.height, depth: 1), to: texture,
                  destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        return texture
    }
}
