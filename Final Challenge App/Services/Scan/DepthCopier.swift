//
//  DepthCopier.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 10/11/26.
//

import CoreVideo
import MeasureKit

nonisolated enum DepthCopier {

    static func copy(depthMap: CVPixelBuffer, confidenceMap: CVPixelBuffer?) -> DepthFrame? {
        guard CVPixelBufferGetPixelFormatType(depthMap) == kCVPixelFormatType_DepthFloat32 else { return nil }
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard let depth: [Float] = values(in: depthMap, width: width, height: height) else { return nil }

        var confidence = [UInt8](repeating: 0, count: width * height)
        if let confidenceMap {
            guard CVPixelBufferGetPixelFormatType(confidenceMap) == kCVPixelFormatType_OneComponent8,
                  CVPixelBufferGetWidth(confidenceMap) == width,
                  CVPixelBufferGetHeight(confidenceMap) == height,
                  let copied: [UInt8] = values(in: confidenceMap, width: width, height: height)
            else { return nil }
            confidence = copied
        }
        return DepthFrame(width: width, height: height, depth: depth, confidence: confidence)
    }

    private static func values<Value>(in buffer: CVPixelBuffer, width: Int, height: Int) -> [Value]? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        var result: [Value] = []
        result.reserveCapacity(width * height)
        for row in 0..<height {
            let start = base.advanced(by: row * bytesPerRow).assumingMemoryBound(to: Value.self)
            result.append(contentsOf: UnsafeBufferPointer(start: start, count: width))
        }
        return result
    }
}
