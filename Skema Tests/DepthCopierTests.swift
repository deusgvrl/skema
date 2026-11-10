//
//  DepthCopierTests.swift
//  Skema Tests
//
//  Created by Muhammad Dzakki Abdullah on 10/11/26.
//

import CoreVideo
import MeasureKit
import Testing
@testable import Final_Challenge_App

@Suite("Depth copier")
struct DepthCopierTests {
    // Width 3 makes each row 12 bytes, which CoreVideo pads, so the padding is skipped in every test.
    let depthValues: [Float] = [0.5, 1, 1.5, 2, 2.5, 3]
    let confidenceValues: [UInt8] = [0, 1, 2, 2, 1, 0]

    @Test("Copies depth and confidence row by row")
    func copiesValues() throws {
        let depthMap = try makePixelBuffer(
            width: 3, height: 2, format: kCVPixelFormatType_DepthFloat32, values: depthValues
        )
        let confidenceMap = try makePixelBuffer(
            width: 3, height: 2, format: kCVPixelFormatType_OneComponent8, values: confidenceValues
        )

        let frame = try #require(DepthCopier.copy(depthMap: depthMap, confidenceMap: confidenceMap))

        #expect(frame.width == 3)
        #expect(frame.height == 2)
        #expect(frame.depth == depthValues)
        #expect(frame.confidence == confidenceValues)
    }

    @Test("No confidence map gives all-low confidence")
    func missingConfidenceIsLow() throws {
        let depthMap = try makePixelBuffer(
            width: 3, height: 2, format: kCVPixelFormatType_DepthFloat32, values: depthValues
        )

        let frame = try #require(DepthCopier.copy(depthMap: depthMap, confidenceMap: nil))

        #expect(frame.depth == depthValues)
        #expect(frame.confidence == [0, 0, 0, 0, 0, 0])
    }

    @Test("A depth map in another format gives nil")
    func wrongDepthFormat() throws {
        let notDepth = try makePixelBuffer(
            width: 3, height: 2, format: kCVPixelFormatType_OneComponent8, values: confidenceValues
        )

        #expect(DepthCopier.copy(depthMap: notDepth, confidenceMap: nil) == nil)
    }

    @Test("A confidence map of another size gives nil")
    func sizeMismatch() throws {
        let depthMap = try makePixelBuffer(
            width: 3, height: 2, format: kCVPixelFormatType_DepthFloat32, values: depthValues
        )
        let smallConfidence = try makePixelBuffer(
            width: 2, height: 2, format: kCVPixelFormatType_OneComponent8, values: [UInt8]([2, 2, 2, 2])
        )

        #expect(DepthCopier.copy(depthMap: depthMap, confidenceMap: smallConfidence) == nil)
    }
}
