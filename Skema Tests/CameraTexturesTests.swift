//
//  CameraTexturesTests.swift
//  Skema Tests
//
//  Created by Amadeus Gavriel on 24/11/26.
//

import CoreVideo
import Metal
import Testing
@testable import Skema_Photo

@MainActor
@Suite(
    "Camera textures",
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "No Metal device here: the texture tests are skipped.")
)
struct CameraTexturesTests {
    /// A device is there: the suite is skipped when it is not (see the trait above).
    private func makeTextures() throws -> CameraTextures {
        let device = try #require(MTLCreateSystemDefaultDevice(), "No Metal device")
        return try #require(CameraTextures(device: device), "No texture cache")
    }

    /// A Metal-ready pixel buffer, like the ones ARKit gives.
    private func makeBuffer(width: Int, height: Int, format: OSType) throws -> CVPixelBuffer {
        let attributes: [CFString: Any] = [
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [String: Any]()
        ]
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, format, attributes as CFDictionary, &buffer
        )
        #expect(status == kCVReturnSuccess)
        return try #require(buffer, "No pixel buffer")
    }

    @Test("R1: a BGRA buffer is not a camera frame, so there are no textures")
    func bgraBufferGivesNoCameraTextures() throws {
        let textures = try makeTextures()
        let buffer = try makeBuffer(width: 16, height: 12, format: kCVPixelFormatType_32BGRA)

        #expect(textures.cameraTextures(from: buffer) == nil)
    }

    @Test("R1: a 420v (video range) buffer is also not accepted, only 420f")
    func videoRangeBufferGivesNoCameraTextures() throws {
        let textures = try makeTextures()
        let buffer = try makeBuffer(
            width: 16, height: 12, format: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        )

        #expect(textures.cameraTextures(from: buffer) == nil)
    }

    @Test("R2: a 420f buffer gives a Y texture and a half-size CbCr texture")
    func cameraBufferGivesYAndCbCrTextures() throws {
        let textures = try makeTextures()
        let buffer = try makeBuffer(
            width: 16, height: 12, format: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        )

        let pair = try #require(textures.cameraTextures(from: buffer))
        let luma = try #require(CVMetalTextureGetTexture(pair.y))
        let cbcr = try #require(CVMetalTextureGetTexture(pair.cbcr))

        #expect(luma.pixelFormat == .r8Unorm)
        #expect(luma.width == 16)
        #expect(luma.height == 12)
        #expect(cbcr.pixelFormat == .rg8Unorm)
        #expect(cbcr.width == 8)
        #expect(cbcr.height == 6)
    }

    @Test("R3: depth and confidence buffers give r32Float and r8Uint textures")
    func depthBuffersGiveDepthAndConfidenceTextures() throws {
        let textures = try makeTextures()
        let depth = try makeBuffer(width: 256, height: 192, format: kCVPixelFormatType_DepthFloat32)
        let confidence = try makeBuffer(width: 256, height: 192, format: kCVPixelFormatType_OneComponent8)

        let pair = try #require(textures.depthTextures(depth: depth, confidence: confidence))
        let depthTexture = try #require(CVMetalTextureGetTexture(pair.depth))
        let confidenceTexture = try #require(pair.confidence.flatMap { CVMetalTextureGetTexture($0) })

        #expect(depthTexture.pixelFormat == .r32Float)
        #expect(depthTexture.width == 256)
        #expect(depthTexture.height == 192)
        #expect(confidenceTexture.pixelFormat == .r8Uint)
        #expect(confidenceTexture.width == 256)
        #expect(confidenceTexture.height == 192)
    }

    @Test("R3: depth without a confidence buffer still works")
    func depthWithoutConfidenceGivesDepthOnly() throws {
        let textures = try makeTextures()
        let depth = try makeBuffer(width: 256, height: 192, format: kCVPixelFormatType_DepthFloat32)

        let pair = try #require(textures.depthTextures(depth: depth, confidence: nil))

        #expect(pair.confidence == nil)
    }

    @Test("R3: a depth buffer in the wrong format gives nil")
    func wrongDepthFormatGivesNil() throws {
        let textures = try makeTextures()
        let wrong = try makeBuffer(width: 256, height: 192, format: kCVPixelFormatType_32BGRA)

        #expect(textures.depthTextures(depth: wrong, confidence: nil) == nil)
    }

    @Test("R3: a confidence buffer in the wrong format gives nil")
    func wrongConfidenceFormatGivesNil() throws {
        let textures = try makeTextures()
        let depth = try makeBuffer(width: 256, height: 192, format: kCVPixelFormatType_DepthFloat32)
        let wrong = try makeBuffer(width: 256, height: 192, format: kCVPixelFormatType_32BGRA)

        #expect(textures.depthTextures(depth: depth, confidence: wrong) == nil)
    }
}
