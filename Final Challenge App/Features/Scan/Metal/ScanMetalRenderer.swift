//
//  ScanMetalRenderer.swift
//  Final Challenge App
//
//  Created by Amadeus Gavriel on 24/11/26.
//
//  Draws the scan screen with plain Metal (Metal renderer, part 2): the camera picture, then the box outlines on top.
//  A line behind a real thing (by the LiDAR depth) is not drawn. It replaces ARView's RealityKit work on this screen.
//

import ARKit
import CoreVideo
import MeasureKit
import Metal
import os
import QuartzCore
import simd

nonisolated private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Skema", category: "MetalScan")

/// The display link delegate of the Metal scan view. Each frame reads `session.currentFrame` and encodes one render
/// pass: the camera quad first, then the outlines (white, `OutlineLayout.opacity`, blended over the picture).
///
/// It is used on the render thread only (A10-121, step 4): the display link calls it there, and its GPU buffers and
/// texture cache are never touched from another thread. The main thread talks to it through the `OutlineInbox`.
nonisolated final class ScanMetalRenderer: NSObject, CAMetalDisplayLinkDelegate {
    /// The colour format of the view and of both pipelines. The view must use the same one.
    static let colorPixelFormat: MTLPixelFormat = .bgra8Unorm

    /// The boxes to outline, by item id. Each frame it takes the inbox's newest ones. On the next draw, the GPU
    /// buffers follow the ones in view (`visibleOutlines`).
    var outlines: [UUID: WorldBox] = [:]

    /// Where the main thread puts the newest outlines and the view size.
    let inbox: OutlineInbox
    private let session: ARSession
    private let queue: any MTLCommandQueue
    private let cameraPipeline: any MTLRenderPipelineState
    private let outlinePipeline: any MTLRenderPipelineState
    private let cameraTextures: CameraTextures
    private let outlineBuffers: OutlineBuffers
    /// 1 x 1 stand-ins, bound when the frame has no depth. The shader does not read them then (hasDepth is 0), but
    /// Metal's API validation may stop the app when a texture the shader names is not bound (inferred).
    private let placeholderDepth: any MTLTexture
    private let placeholderConfidence: any MTLTexture

    /// Returns nil when the shader library, a pipeline, the command queue, the texture cache or a stand-in texture
    /// cannot be made.
    init?(device: any MTLDevice, session: ARSession, inbox: OutlineInbox = OutlineInbox()) {
        guard let library = device.makeDefaultLibrary() else {
            log.error("Metal renderer: no default shader library")
            return nil
        }
        guard let cameraPipeline = Self.makePipeline(device: device, library: library, vertex: "cameraVertex",
                                                     fragment: "cameraFragment", blends: false) else {
            log.error("Metal renderer: the camera pipeline could not be made")
            return nil
        }
        guard let outlinePipeline = Self.makePipeline(device: device, library: library, vertex: "outlineVertex",
                                                      fragment: "outlineFragment", blends: true) else {
            log.error("Metal renderer: the outline pipeline could not be made")
            return nil
        }
        guard let queue = device.makeCommandQueue() else {
            log.error("Metal renderer: no command queue")
            return nil
        }
        guard let cameraTextures = CameraTextures(device: device) else {
            log.error("Metal renderer: no texture cache")
            return nil
        }
        guard let placeholderDepth = Self.makePlaceholder(device: device, format: .r32Float),
              let placeholderConfidence = Self.makePlaceholder(device: device, format: .r8Uint) else {
            log.error("Metal renderer: the stand-in textures could not be made")
            return nil
        }
        self.session = session
        self.inbox = inbox
        self.queue = queue
        self.cameraPipeline = cameraPipeline
        self.outlinePipeline = outlinePipeline
        self.cameraTextures = cameraTextures
        self.outlineBuffers = OutlineBuffers(device: device)
        self.placeholderDepth = placeholderDepth
        self.placeholderConfidence = placeholderConfidence
        super.init()
    }

    /// The numbers the shaders need for one frame. `hasDepth` is true only when the frame has both a depth and a
    /// confidence texture (the outline shader reads both).
    nonisolated static func uniforms(camera: CameraModel, viewSize: CGSize, hasDepth: Bool) -> ScanUniforms {
        let corners = ScanProjection.pictureQuadTexCoords(camera: camera, viewSize: viewSize)
        return ScanUniforms(
            viewProjection: ScanProjection.viewProjection(camera: camera, viewSize: viewSize),
            quadTexCoords: (corners[0], corners[1], corners[2], corners[3]),
            pictureSize: camera.imageResolution,
            occlusionMargin: OcclusionRule.margin,
            minConfidence: UInt32(OcclusionRule.minConfidence),
            maxRange: OcclusionRule.maxRange,
            hasDepth: hasDepth ? 1 : 0,
            lineColor: SIMD4(1, 1, 1, OutlineLayout.opacity)
        )
    }

    /// The boxes the camera can see (A10-121). Only these get GPU buffers: a box that is off the screen loses its
    /// buffers (`OutlineBuffers.update` drops a missing id) and builds them again when it is back in view.
    nonisolated static func visibleOutlines(_ outlines: [UUID: WorldBox], camera: CameraModel) -> [UUID: WorldBox] {
        outlines.filter { FieldOfView.contains($0.value, camera: camera) }
    }

    /// One frame, on the render thread: the display link gives the drawable to draw into.
    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        draw(into: update.drawable)
    }

    /// One frame: one command buffer, one render pass. With no AR frame (or no camera picture) the drawable is only
    /// cleared.
    private func draw(into drawable: any CAMetalDrawable) {
        let latest = inbox.snapshot()
        outlines = latest.outlines
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }

        // The size in points: the line thickness (OutlineLayout.thickness) is in points.
        let viewSize = latest.viewSize
        if viewSize.width > 0, viewSize.height > 0, let frame = session.currentFrame,
           let picture = cameraTextures.cameraTextures(from: frame.capturedImage),
           let luma = CVMetalTextureGetTexture(picture.y), let chroma = CVMetalTextureGetTexture(picture.cbcr) {
            let depthPair = frame.sceneDepth.flatMap {
                cameraTextures.depthTextures(depth: $0.depthMap, confidence: $0.confidenceMap)
            }
            // Both or none: the outline shader reads the confidence whenever it reads the depth.
            let sceneDepth = depthPair.flatMap { pair -> (depth: any MTLTexture, confidence: any MTLTexture)? in
                guard let depth = CVMetalTextureGetTexture(pair.depth),
                      let confidence = pair.confidence.flatMap({ CVMetalTextureGetTexture($0) }) else { return nil }
                return (depth, confidence)
            }
            encode(into: encoder, camera: CameraModel(frame.camera), viewSize: viewSize,
                   picture: (luma, chroma), sceneDepth: sceneDepth)
            // Apple's rule: the CVMetalTextures must live until the GPU is done with their textures.
            let kept = KeptTextures(textures: [picture.y, picture.cbcr]
                                    + [depthPair?.depth, depthPair?.confidence].compactMap { $0 })
            commands.addCompletedHandler { @Sendable _ in
                withExtendedLifetime(kept) {}
            }
        }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
        cameraTextures.flush()
    }

    /// Encodes the camera quad (when `picture` is given), then the outlines of the boxes in view, into an open render
    /// pass. A line can be hidden only when `sceneDepth` (the LiDAR depth and its confidence) is given. `viewSize` is
    /// in points.
    func encode(into encoder: any MTLRenderCommandEncoder, camera: CameraModel, viewSize: CGSize,
                picture: (luma: any MTLTexture, chroma: any MTLTexture)?,
                sceneDepth: (depth: any MTLTexture, confidence: any MTLTexture)?) {
        var uniforms = Self.uniforms(camera: camera, viewSize: viewSize, hasDepth: sceneDepth != nil)
        let uniformsLength = MemoryLayout<ScanUniforms>.stride

        if let picture {
            encoder.setRenderPipelineState(cameraPipeline)
            encoder.setVertexBytes(&uniforms, length: uniformsLength, index: 0)
            encoder.setFragmentTexture(picture.luma, index: 0)
            encoder.setFragmentTexture(picture.chroma, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        let cameraPosition = SIMD3(camera.cameraToWorld.columns.3.x, camera.cameraToWorld.columns.3.y,
                                   camera.cameraToWorld.columns.3.z)
        let focalLength = ScanProjection.focalLength(camera: camera, viewSize: viewSize)
        outlineBuffers.update(Self.visibleOutlines(outlines, camera: camera)) { box in
            OutlineMesh.radius(for: box, cameraPosition: cameraPosition, focalLength: focalLength)
        }
        guard !outlineBuffers.entries.isEmpty else { return }
        encoder.setRenderPipelineState(outlinePipeline)
        // Draw each tube once: skip its back faces. OutlineMesh makes outside faces counter-clockwise, and
        // ScanProjection is a rotation, not a mirror, so they stay counter-clockwise on screen.
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.back)
        encoder.setVertexBytes(&uniforms, length: uniformsLength, index: 1)
        encoder.setFragmentBytes(&uniforms, length: uniformsLength, index: 0)
        encoder.setFragmentTexture(sceneDepth?.depth ?? placeholderDepth, index: 0)
        encoder.setFragmentTexture(sceneDepth?.confidence ?? placeholderConfidence, index: 1)
        for entry in outlineBuffers.entries.values {
            encoder.setVertexBuffer(entry.vertexBuffer, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: entry.indexCount, indexType: .uint32,
                                          indexBuffer: entry.indexBuffer, indexBufferOffset: 0)
        }
    }

    /// A render pipeline for `colorPixelFormat` with no depth attachment. `blends`: source-over alpha blending.
    private static func makePipeline(device: any MTLDevice, library: any MTLLibrary, vertex: String,
                                     fragment: String, blends: Bool) -> (any MTLRenderPipelineState)? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: vertex)
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        guard descriptor.vertexFunction != nil, descriptor.fragmentFunction != nil else { return nil }
        let color = descriptor.colorAttachments[0]
        color?.pixelFormat = colorPixelFormat
        if blends {
            color?.isBlendingEnabled = true
            color?.sourceRGBBlendFactor = .sourceAlpha
            color?.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color?.sourceAlphaBlendFactor = .one
            color?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// Holds a frame's CVMetalTextures until the command buffer is done. `@unchecked Sendable`: the completed handler
    /// runs on another thread, but it only keeps the objects alive and never reads them.
    private struct KeptTextures: @unchecked Sendable {
        let textures: [CVMetalTexture]
    }

    /// A 1 x 1 texture the shader may name but never reads (see `placeholderDepth`).
    private static func makePlaceholder(device: any MTLDevice, format: MTLPixelFormat) -> (any MTLTexture)? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: 1, height: 1,
                                                                  mipmapped: false)
        descriptor.storageMode = .private
        descriptor.usage = .shaderRead
        return device.makeTexture(descriptor: descriptor)
    }
}
