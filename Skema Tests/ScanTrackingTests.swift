//
//  ScanTrackingTests.swift
//  Skema Tests
//
//  Created by Muhammad Dzakki Abdullah on 10/11/26.
//

import ARKit
import Foundation
import Testing
@testable import Final_Challenge_App

@Suite("Tracking and errors from ARKit")
struct ScanTrackingTests {
    @Test("Each ARKit tracking state maps to its scan tracking", arguments: [
        (ARCamera.TrackingState.normal, ScanTracking.normal),
        (.notAvailable, .notAvailable),
        (.limited(.initializing), .limited(.initializing)),
        (.limited(.excessiveMotion), .limited(.excessiveMotion)),
        (.limited(.insufficientFeatures), .limited(.insufficientFeatures)),
        (.limited(.relocalizing), .limited(.relocalizing))
    ])
    func mapsTrackingState(state: ARCamera.TrackingState, expected: ScanTracking) {
        #expect(ScanTracking(state) == expected)
    }

    @Test("Camera access denied becomes cameraDenied")
    func cameraUnauthorized() {
        #expect(ScanSessionError(ARError(.cameraUnauthorized)) == .cameraDenied)
    }

    @Test("Any other error keeps its description")
    func otherError() {
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sensor failed"])

        #expect(ScanSessionError(error) == .sessionFailed("Sensor failed"))
    }
}
