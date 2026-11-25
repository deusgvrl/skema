//
//  ScanMetalRendererTests.swift
//  Skema Tests
//
//  Created by Amadeus Gavriel on 24/11/26.
//
//  The Metal renderer: its uniforms for one frame (R4), that its shaders and pipelines build, and that its outline
//  pass really hides a box behind a nearer LiDAR depth. Shared camera: fx = fy = 1500, centre (960, 720),
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
        #expect(uniforms.lineColor == SIMD4(1, 1, 1, OutlineLayout.opacity))
    }

    @Test("The shaders compile and the pipelines build on this device")
    func initBuildsThePipelines() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())

        #expect(ScanMetalRenderer(device: device, session: ARSession()) != nil)
    }

    @Test("The outline pass hides a box behind nearer LiDAR depth and shows it in front of farther depth")
    func outlinePassUsesTheDepth() throws {
        // A 40 cm box 2 m in front of the camera (line depths 1.8 to 2.2 m).
        let inFront = try whitePixelCount(sceneDepth: 1.0)
        let behind = try whitePixelCount(sceneDepth: 3.0)

        #expect(inFront == 0, "Scene depth 1 m is in front of the box: no line pixel may show")
        #expect(behind > 0, "Scene depth 3 m is behind the box: the lines must show")
    }

    @Test("A line is drawn once: the back face of a tube is culled, so no pixel gets two layers of white")
    func outlineIsOneLayerOfWhite() throws {
        let result = try renderOutline(sceneDepth: 3.0)

        // One layer: white at OutlineLayout.opacity over black is 0.7 x 255 = about 179. Two layers would be about 232.
        // The brightest pixel is not used: where two different edges (or a corner) cross on the screen, two layers are
        // right. The most common line value is one tube's own layer.
        let oneLayer = Int((OutlineLayout.opacity * 255).rounded())
        #expect(abs(result.commonRed - oneLayer) <= 12,
                "Most common line value \(result.commonRed), one layer \(oneLayer). Histogram: \(result.histogram)")
    }

    /// Draws one box with the renderer's outline pass into a 64 x 128 bgra8Unorm target cleared to black, with a
    /// 1 x 1 depth texture of `sceneDepth` metres and high confidence, and counts the white-ish pixels.
    private func whitePixelCount(sceneDepth: Float) throws -> Int {
        try renderOutline(sceneDepth: sceneDepth).whitePixels
    }

    private struct OutlineRender {
        let whitePixels: Int
        /// The most common non-black red value.
        let commonRed: Int
        let histogram: String
    }

    /// The render described at `whitePixelCount`, with its white-ish pixel count and its red values.
    private func renderOutline(sceneDepth: Float) throws -> OutlineRender {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(ScanMetalRenderer(device: device, session: ARSession()))
        renderer.outlines = [UUID(): WorldBox(min: SIMD3(-0.2, -0.2, -2.2), max: SIMD3(0.2, 0.2, -1.8))]
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
        renderer.encode(into: encoder, camera: sharedCamera(), viewSize: CGSize(width: width, height: height),
                        picture: nil, sceneDepth: (depth, confidence))
        encoder.endEncoding()
        let blit = try #require(commands.makeBlitCommandEncoder())
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: readBack,
                  destinationOffset: 0, destinationBytesPerRow: width * 4, destinationBytesPerImage: width * height * 4)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        #expect(commands.status == .completed)

        // White at 70% over black is about 178 in every channel.
        let pixels = UnsafeBufferPointer(
            start: readBack.contents().bindMemory(to: UInt8.self, capacity: width * height * 4),
            count: width * height * 4
        )
        let starts = stride(from: 0, to: pixels.count, by: 4)
        let white = starts.filter { pixels[$0] >= 128 && pixels[$0 + 1] >= 128 && pixels[$0 + 2] >= 128 }.count
        // bgra8Unorm: the red channel is byte 2 of each pixel.
        var counts: [Int: Int] = [:]
        for index in starts where pixels[index + 2] > 0 { counts[Int(pixels[index + 2]), default: 0] += 1 }
        let top = counts.sorted { $0.value > $1.value }.prefix(6)
        return OutlineRender(whitePixels: white, commonRed: top.first?.key ?? 0,
                             histogram: top.map { "\($0.key): \($0.value)" }.joined(separator: ", "))
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
