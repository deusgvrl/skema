//
//  ScanShadersTests.swift
//  Skema Tests
//
//  Created by Amadeus Gavriel on 24/11/26.
//

import Foundation
import Metal
import MeasureKit
import simd
import Testing
@testable import Skema_Photo

@MainActor
@Suite(
    "Scan shaders",
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "No Metal device here: the shader tests are skipped.")
)
struct ScanShadersTests {
    /// One occlusion input: line depth and scene depth in metres, and the LiDAR confidence.
    private struct OcclusionCase {
        let line: Float
        let scene: Float
        let confidence: UInt8
    }

    /// The occlusion inputs of M9–M13a plus the 3 cm edge pair.
    private let occlusionCases: [OcclusionCase] = [
        OcclusionCase(line: 2.0, scene: 1.5, confidence: 2),     // M9: hidden
        OcclusionCase(line: 2.0, scene: 2.5, confidence: 2),     // M10: shows
        OcclusionCase(line: 2.0, scene: 1.99, confidence: 2),    // M11: inside the margin, shows
        OcclusionCase(line: 2.0, scene: 0, confidence: 2),       // M12: no depth, shows
        OcclusionCase(line: 2.0, scene: .nan, confidence: 2),    // M12: NaN depth, shows
        OcclusionCase(line: 2.0, scene: 1.0, confidence: 0),     // M13: low confidence, shows
        OcclusionCase(line: 6.0, scene: 5.5, confidence: 2),     // M13a: beyond 5 m, shows
        OcclusionCase(line: 2.0, scene: 1.969, confidence: 2),   // 3 cm edge: hidden
        OcclusionCase(line: 2.0, scene: 1.971, confidence: 2)    // 3 cm edge: shows
    ]

    /// The shaders are in the app's default library (the test host is the app).
    private func makeDeviceAndLibrary() throws -> (any MTLDevice, any MTLLibrary) {
        let device = try #require(MTLCreateSystemDefaultDevice(), "No Metal device")
        let library = try device.makeDefaultLibrary(bundle: Bundle(for: CameraTextures.self))
        return (device, library)
    }

    /// Uniforms with the OcclusionRule numbers. The other fields are not used by these tests.
    private func makeUniforms(hasDepth: Bool) -> ScanUniforms {
        let corner = SIMD2<Float>(0, 0)
        return ScanUniforms(
            viewProjection: matrix_identity_float4x4,
            quadTexCoords: (corner, SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1)),
            pictureSize: SIMD2(1, 1),
            occlusionMargin: OcclusionRule.margin,
            minConfidence: UInt32(OcclusionRule.minConfidence),
            maxRange: OcclusionRule.maxRange,
            hasDepth: hasDepth ? 1 : 0,
            lineColor: SIMD4(1, 1, 1, 1)
        )
    }

    /// Runs `occlusionRuleKernel` on every case and returns its 0/1 answers.
    private func kernelAnswers(hasDepth: Bool) throws -> [UInt32] {
        let (device, library) = try makeDeviceAndLibrary()
        let function = try #require(library.makeFunction(name: "occlusionRuleKernel"))
        let pipeline = try device.makeComputePipelineState(function: function)
        let count = occlusionCases.count
        let lines = occlusionCases.map(\.line)
        let scenes = occlusionCases.map(\.scene)
        let confidences = occlusionCases.map { UInt32($0.confidence) }
        var uniforms = makeUniforms(hasDepth: hasDepth)
        let output = try #require(device.makeBuffer(length: count * MemoryLayout<UInt32>.stride))

        let queue = try #require(device.makeCommandQueue())
        let commands = try #require(queue.makeCommandBuffer())
        let encoder = try #require(commands.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setBytes(lines, length: count * MemoryLayout<Float>.stride, index: 0)
        encoder.setBytes(scenes, length: count * MemoryLayout<Float>.stride, index: 1)
        encoder.setBytes(confidences, length: count * MemoryLayout<UInt32>.stride, index: 2)
        encoder.setBuffer(output, offset: 0, index: 3)
        encoder.setBytes(&uniforms, length: MemoryLayout<ScanUniforms>.stride, index: 4)
        encoder.dispatchThreadgroups(
            MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        #expect(commands.status == .completed)

        let pointer = output.contents().bindMemory(to: UInt32.self, capacity: count)
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    @Test("Layout: the Swift ScanUniforms has the same size and field offsets as the Metal struct")
    func uniformsLayoutMatchesMetal() async throws {
        let (device, library) = try makeDeviceAndLibrary()
        let function = try #require(library.makeFunction(name: "occlusionRuleKernel"))
        let (_, reflection) = try await device.makeComputePipelineState(
            function: function, options: [.bindingInfo, .bufferTypeInfo]
        )
        let binding = try #require(
            reflection?.bindings.first { $0.name == "uniforms" } as? any MTLBufferBinding,
            "The kernel has no 'uniforms' buffer"
        )

        #expect(MemoryLayout<ScanUniforms>.stride == ScanUniforms.metalSize)
        #expect(binding.bufferDataSize == MemoryLayout<ScanUniforms>.stride)

        let metalOffsets = Dictionary(
            uniqueKeysWithValues: (binding.bufferStructType?.members ?? []).map { ($0.name, $0.offset) }
        )
        let swiftOffsets: [String: Int?] = [
            "viewProjection": MemoryLayout<ScanUniforms>.offset(of: \.viewProjection),
            "quadTexCoords": MemoryLayout<ScanUniforms>.offset(of: \.quadTexCoords),
            "pictureSize": MemoryLayout<ScanUniforms>.offset(of: \.pictureSize),
            "occlusionMargin": MemoryLayout<ScanUniforms>.offset(of: \.occlusionMargin),
            "minConfidence": MemoryLayout<ScanUniforms>.offset(of: \.minConfidence),
            "maxRange": MemoryLayout<ScanUniforms>.offset(of: \.maxRange),
            "hasDepth": MemoryLayout<ScanUniforms>.offset(of: \.hasDepth),
            "lineColor": MemoryLayout<ScanUniforms>.offset(of: \.lineColor)
        ]
        #expect(metalOffsets.count == swiftOffsets.count)
        for (name, offset) in swiftOffsets {
            #expect(metalOffsets[name] == offset, "Offset of \(name)")
        }
    }

    @Test("R5: the GPU occlusion test gives the same answer as OcclusionRule for M9–M13a and the 3 cm edge")
    func gpuOcclusionMatchesOcclusionRule() throws {
        let answers = try kernelAnswers(hasDepth: true)

        #expect(answers.count == occlusionCases.count)
        for (index, item) in occlusionCases.enumerated() {
            let expected = OcclusionRule.isHidden(
                lineDepth: item.line, sceneDepth: item.scene, confidence: item.confidence
            )
            #expect(answers[index] == (expected ? 1 : 0), "Case \(index): \(item)")
        }
    }

    @Test("R5: with no depth texture (hasDepth 0) the line is never hidden")
    func noDepthNeverHides() throws {
        let answers = try kernelAnswers(hasDepth: false)

        #expect(answers == Array(repeating: 0, count: occlusionCases.count))
    }

    @Test("R6: cameraFragment turns Y 0.5, Cb 0.25, Cr 0.75 into Apple's RGB within 1/255")
    func cameraFragmentUsesApplesYCbCrMatrix() throws {
        let (device, library) = try makeDeviceAndLibrary()
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "cameraVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "cameraFragment")
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        // The texture values as bytes: 0.5, 0.25 and 0.75 rounded to 8 bits.
        let yByte = UInt8((0.5 * 255).rounded()), cbByte = UInt8((0.25 * 255).rounded())
        let crByte = UInt8((0.75 * 255).rounded())
        let queue = try #require(device.makeCommandQueue())
        let luma = try makeTexture(device: device, queue: queue, format: .r8Unorm, bytes: [yByte])
        let chroma = try makeTexture(device: device, queue: queue, format: .rg8Unorm, bytes: [cbByte, crByte])
        let target = try makeTexture(device: device, queue: queue, format: .rgba8Unorm, bytes: [0, 0, 0, 0])
        let readBack = try #require(device.makeBuffer(length: 4))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        var uniforms = makeUniforms(hasDepth: false)
        let commands = try #require(queue.makeCommandBuffer())
        let encoder = try #require(commands.makeRenderCommandEncoder(descriptor: pass))
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ScanUniforms>.stride, index: 0)
        encoder.setFragmentTexture(luma, index: 0)
        encoder.setFragmentTexture(chroma, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        let blit = try #require(commands.makeBlitCommandEncoder())
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                  sourceSize: MTLSize(width: 1, height: 1, depth: 1), to: readBack,
                  destinationOffset: 0, destinationBytesPerRow: 4, destinationBytesPerImage: 4)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        #expect(commands.status == .completed)

        // Apple's ycbcrToRGBTransform (ARFrame.h), on the values the shader reads.
        let appleMatrix = simd_float4x4(columns: (
            SIMD4(1.0, 1.0, 1.0, 0.0),
            SIMD4(0.0, -0.3441, 1.7720, 0.0),
            SIMD4(1.4020, -0.7141, 0.0, 0.0),
            SIMD4(-0.7010, 0.5291, -0.8860, 1.0)
        ))
        let ycbcr = SIMD4(Float(yByte) / 255, Float(cbByte) / 255, Float(crByte) / 255, 1)
        let expected = simd_clamp(appleMatrix * ycbcr, SIMD4(repeating: 0), SIMD4(repeating: 1))
        let pixel = readBack.contents().bindMemory(to: UInt8.self, capacity: 4)
        for channel in 0..<3 {
            let actual = Float(pixel[channel]) / 255
            #expect(abs(actual - expected[channel]) <= 1.0 / 255, "Channel \(channel)")
        }
    }

    /// A 1×1 private texture filled through a blit (the simulator needs private textures for rendering).
    private func makeTexture(device: any MTLDevice, queue: any MTLCommandQueue,
                             format: MTLPixelFormat, bytes: [UInt8]) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: 1, height: 1, mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .renderTarget]
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let source = try #require(device.makeBuffer(bytes: bytes, length: bytes.count))
        let commands = try #require(queue.makeCommandBuffer())
        let blit = try #require(commands.makeBlitCommandEncoder())
        blit.copy(from: source, sourceOffset: 0, sourceBytesPerRow: bytes.count, sourceBytesPerImage: bytes.count,
                  sourceSize: MTLSize(width: 1, height: 1, depth: 1), to: texture,
                  destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        return texture
    }
}
