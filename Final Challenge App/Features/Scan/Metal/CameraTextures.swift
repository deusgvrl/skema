//
//  CameraTextures.swift
//  Final Challenge App
//
//  Created by Amadeus Gavriel on 24/11/26.
//
//  Turns ARKit pixel buffers into Metal textures (Metal renderer, part 2). It uses one CVMetalTextureCache, so no
//  pixels are copied: the texture reads the same memory as the buffer.
//

import CoreVideo
import Metal

/// Makes Metal textures from camera, depth and confidence buffers.
///
/// Keep the returned `CVMetalTexture` objects alive until the command buffer that uses them is done (Apple's rule).
/// If one is freed early, the GPU can read memory that is already reused.
final class CameraTextures {
    private let cache: CVMetalTextureCache

    /// Returns nil only when the texture cache cannot be made.
    init?(device: any MTLDevice) {
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess,
              let cache else { return nil }
        self.cache = cache
    }

    /// The two camera planes: Y (brightness, `r8Unorm`) and CbCr (colour, `rg8Unorm`, half size).
    /// Returns nil unless the buffer is `420YpCbCr8BiPlanarFullRange`.
    func cameraTextures(from pixelBuffer: CVPixelBuffer) -> (y: CVMetalTexture, cbcr: CVMetalTexture)? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
              let luma = texture(from: pixelBuffer, format: .r8Unorm, plane: 0),
              let cbcr = texture(from: pixelBuffer, format: .rg8Unorm, plane: 1) else { return nil }
        return (luma, cbcr)
    }

    /// The depth texture (`r32Float`) and, when given, the confidence texture (`r8Uint`).
    /// Returns nil when the depth buffer is not `DepthFloat32`, or the confidence buffer is not `OneComponent8`.
    func depthTextures(
        depth: CVPixelBuffer,
        confidence: CVPixelBuffer?
    ) -> (depth: CVMetalTexture, confidence: CVMetalTexture?)? {
        guard CVPixelBufferGetPixelFormatType(depth) == kCVPixelFormatType_DepthFloat32,
              let depthTexture = texture(from: depth, format: .r32Float, plane: 0) else { return nil }
        guard let confidence else { return (depthTexture, nil) }
        guard CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8,
              let confidenceTexture = texture(from: confidence, format: .r8Uint, plane: 0) else { return nil }
        return (depthTexture, confidenceTexture)
    }

    /// A flush once per frame lets the cache free unused textures (inferred, not checked in Apple's docs).
    func flush() {
        CVMetalTextureCacheFlush(cache, 0)
    }

    /// One plane of a buffer as a texture. A buffer with no planes (depth, confidence) is plane 0 of itself.
    private func texture(from buffer: CVPixelBuffer, format: MTLPixelFormat, plane: Int) -> CVMetalTexture? {
        let isPlanar = CVPixelBufferIsPlanar(buffer)
        let width = isPlanar ? CVPixelBufferGetWidthOfPlane(buffer, plane) : CVPixelBufferGetWidth(buffer)
        let height = isPlanar ? CVPixelBufferGetHeightOfPlane(buffer, plane) : CVPixelBufferGetHeight(buffer)
        var texture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, buffer, nil, format, width, height, plane, &texture
        )
        return status == kCVReturnSuccess ? texture : nil
    }
}
