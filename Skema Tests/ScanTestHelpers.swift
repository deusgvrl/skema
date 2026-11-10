//
//  ScanTestHelpers.swift
//  Skema Tests
//
//  Created by Muhammad Dzakki Abdullah on 10/11/26.
//

import CoreVideo
import Testing
import Foundation
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
