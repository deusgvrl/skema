//
//  ScanTestHelpers.swift
//  Skema Tests
//
//  Created by Muhammad Dzakki Abdullah on 10/11/26.
//

import CoreVideo
import Testing
import Foundation
import ARKit
import MeasureKit
@testable import Final_Challenge_App

func makePixelBuffer<Value>(width: Int, height: Int, format: OSType, values: [Value]) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, nil, &buffer)
    let pixelBuffer = try #require(buffer)

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    let base = try #require(CVPixelBufferGetBaseAddress(pixelBuffer))
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    for row in 0..<height {
        let rowStart = base.advanced(by: row * bytesPerRow).assumingMemoryBound(to: Value.self)
        for column in 0..<width {
            rowStart[column] = values[row * width + column]
        }
    }
    return pixelBuffer
}

func makePlane(worldY: Float, isFloor: Bool = false, area: Float = 1, id: UUID = UUID()) -> ScanPlane {
    ScanPlane(id: id, worldY: worldY, isFloor: isFloor, area: area)
}

func collect<Element>(_ stream: AsyncStream<Element>) async -> [Element] {
    var values: [Element] = []
    for await value in stream {
        values.append(value)
    }
    return values
}

func makeScanFrame(timestamp: TimeInterval) throws -> ScanFrame {
    let image = try makePixelBuffer(
        width: 2, height: 2, format: kCVPixelFormatType_32BGRA, values: [UInt32](repeating: 0, count: 4)
    )
    return ScanFrame(
        timestamp: timestamp,
        image: image,
        orientation: .right,
        camera: CameraModel(
            intrinsics: matrix_identity_float3x3,
            imageResolution: SIMD2(2, 2),
            cameraToWorld: matrix_identity_float4x4
        ),
        depth: nil,
        tracking: .normal,
        ambientIntensity: nil,
        planes: []
    )
}

/// Stands in for `ARSession` and records what `ScanSession` asks of it.
final class FakeARSession: ARSessionControlling, @unchecked Sendable {
    weak var delegate: (any ARSessionDelegate)?
    var delegateQueue: DispatchQueue?
    private(set) var runs: [(configuration: ARConfiguration, options: ARSession.RunOptions)] = []
    private(set) var pauseCount = 0

    func run(_ configuration: ARConfiguration, options: ARSession.RunOptions) {
        runs.append((configuration, options))
    }

    func pause() {
        pauseCount += 1
    }
}

func makeDepth(width: Int, height: Int, depth: Float, confidence: UInt8 = 2) -> DepthFrame {
    DepthFrame(
        width: width,
        height: height,
        depth: [Float](repeating: depth, count: width * height),
        confidence: [UInt8](repeating: confidence, count: width * height)
    )
}

/// A pinhole camera looking down -Z, with the image centre in the middle.
func makeCamera(size: Float, focal: Float, position: SIMD3<Float> = .zero) -> CameraModel {
    var cameraToWorld = matrix_identity_float4x4
    cameraToWorld.columns.3 = SIMD4(position, 1)
    return CameraModel(
        intrinsics: simd_float3x3(columns: (
            SIMD3(focal, 0, 0),
            SIMD3(0, focal, 0),
            SIMD3(size / 2, size / 2, 1)
        )),
        imageResolution: SIMD2(size, size),
        cameraToWorld: cameraToWorld
    )
}

