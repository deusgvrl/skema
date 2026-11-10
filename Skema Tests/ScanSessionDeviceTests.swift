//
//  ScanSessionDeviceTests.swift
//  Skema Tests
//
//  Created by Muhammad Dzakki Abdullah on 10/11/26.
//

import Foundation
import MeasureKit
import Testing
@testable import Final_Challenge_App

/// Runs the real camera and LiDAR. Skipped in the Simulator and on iPhones without LiDAR.
/// On the first run iOS asks for camera access: allow it, point the iPhone at the room, and run again.
@Suite("Scan session on a LiDAR iPhone", .enabled(if: ScanSession.deviceSupportsLiDAR()))
struct ScanSessionDeviceTests {
    @Test("Delivers frames with depth at about 15 per second, then stops", .timeLimit(.minutes(1)))
    func deliversFramesWithDepth() async throws {
        let scan = ScanSession()
        let frames = scan.frames()
        try scan.start()

        // Keep numbers only, never the frames themselves.
        var timestamps: [TimeInterval] = []
        var depthSizes: [Int] = []
        for await frame in frames {
            timestamps.append(frame.timestamp)
            if let depth = frame.depth {
                #expect(depth.depth.count == depth.width * depth.height)
                #expect(depth.confidence.count == depth.depth.count)
                depthSizes.append(depth.width * depth.height)
            }
            if timestamps.count == 30 {
                break
            }
        }
        scan.stop()

        #expect(scan.state == .stopped, "If this says failed(cameraDenied), allow camera access and run again.")
        #expect(timestamps.count == 30)
        #expect(!depthSizes.isEmpty)
        let seconds = try #require(timestamps.last) - (try #require(timestamps.first))
        #expect(Double(timestamps.count - 1) / seconds <= 16)
    }
}
