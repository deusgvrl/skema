//
//  ScanGuidanceTests.swift
//  Skema Tests
//
//  Created by Muhammad Dzakki Abdullah on 12/11/26.
//

import Foundation
import MeasureKit
import Testing
@testable import Skema_Photo

@Suite("Scan guidance: tips when the scan goes badly")
struct ScanGuidanceTests {

    let near = makeDepth(width: 8, height: 8, depth: 1)
    let far = makeDepth(width: 8, height: 8, depth: 6)

    @Test("Tracking that goes well in a lit room with the set near gives no tip")
    func allGood() {
        let tip = ScanGuidance.guidance(tracking: .normal, ambientIntensity: 1000, depth: near)

        #expect(tip == nil)
    }

    @Test("While tracking is limited in a lit room there is no tip, even far: Apple's coaching screen shows instead",
          arguments: [
            ScanTracking.limited(.initializing), .limited(.excessiveMotion), .limited(.relocalizing),
            .limited(.insufficientFeatures), .limited(.other), .notAvailable
          ])
    func limitedTracking(tracking: ScanTracking) {
        let tip = ScanGuidance.guidance(tracking: tracking, ambientIntensity: 1000, depth: far)

        #expect(tip == nil)
    }

    @Test("A dark room asks for more light whatever the tracking, so the tip stays up while tracking comes and goes",
          arguments: [
            ScanTracking.normal, .limited(.initializing), .limited(.excessiveMotion), .limited(.relocalizing),
            .limited(.insufficientFeatures), .limited(.other), .notAvailable
          ])
    func darkInEveryTrackingState(tracking: ScanTracking) {
        let tip = ScanGuidance.guidance(tracking: tracking, ambientIntensity: 100, depth: far)

        #expect(tip == .moreLight)
    }

    @Test("A dark room asks for more light")
    func dark() {
        let tip = ScanGuidance.guidance(tracking: .normal, ambientIntensity: 100, depth: near)

        #expect(tip == .moreLight)
    }

    @Test("No light estimate is not dark")
    func noLightEstimate() {
        let tip = ScanGuidance.guidance(tracking: .normal, ambientIntensity: nil, depth: near)

        #expect(tip == nil)
    }

    @Test("Everything beyond 5 m asks to move closer")
    func tooFar() {
        let tip = ScanGuidance.guidance(tracking: .normal, ambientIntensity: 1000, depth: far)

        #expect(tip == .moveCloser)
    }

    @Test("No confident depth at all asks to move closer")
    func noConfidentDepth() {
        let unsure = makeDepth(width: 8, height: 8, depth: 1, confidence: 0)

        let tip = ScanGuidance.guidance(tracking: .normal, ambientIntensity: 1000, depth: unsure)

        #expect(tip == .moveCloser)
    }

    @Test("A frame without depth gives no distance tip")
    func noDepth() {
        let tip = ScanGuidance.guidance(tracking: .normal, ambientIntensity: 1000, depth: nil)

        #expect(tip == nil)
    }

    @Test("Dark wins over far")
    func priority() {
        let tip = ScanGuidance.guidance(tracking: .normal, ambientIntensity: 100, depth: far)

        #expect(tip == .moreLight)
    }

    @Test("The tips read as approved for the centred instruction (23 Nov)", arguments: [
        (ScanGuidance.moreLight, "More light needed"),
        (.moveCloser, "Move closer"),
        (.floorNotFound, "Floor not found yet")
    ])
    func messages(tip: ScanGuidance, expected: String) {
        #expect(tip.message == expected)
    }

}

@Suite("Guidance hold: tips do not flicker")
struct GuidanceHoldTests {
    @Test("A tip shows after it held for 0.5 s")
    func showsAfterHold() {
        var hold = GuidanceHold()

        let early = hold.update(.moveCloser, at: 0)
        let stillEarly = hold.update(.moveCloser, at: 0.4)
        let shown = hold.update(.moveCloser, at: 0.5)

        #expect(early == nil)
        #expect(stillEarly == nil)
        #expect(shown == .moveCloser)
    }

    @Test("The tip goes 0.5 s after tracking recovers")
    func hidesAfterRecovery() {
        var hold = GuidanceHold()
        _ = hold.update(.moveCloser, at: 0)
        _ = hold.update(.moveCloser, at: 0.5)

        let stillShown = hold.update(nil, at: 1.0)
        let hidden = hold.update(nil, at: 1.5)

        #expect(stillShown == .moveCloser)
        #expect(hidden == nil)
    }

    @Test("A problem shorter than 0.5 s never shows")
    func briefProblemIgnored() {
        var hold = GuidanceHold()

        _ = hold.update(.moveCloser, at: 0)
        _ = hold.update(nil, at: 0.2)
        let later = hold.update(nil, at: 1)

        #expect(later == nil)
    }

    @Test("Steps of 0.1 s add up to 0.5 s")
    func smallSteps() {
        var hold = GuidanceHold()
        var shown: ScanGuidance?

        for step in 0...5 {
            shown = hold.update(.moreLight, at: Double(step) * 0.1)
        }

        #expect(shown == .moreLight)
    }

    @Test("A different tip replaces the shown one after 0.5 s")
    func switchesTips() {
        var hold = GuidanceHold()
        _ = hold.update(.moveCloser, at: 0)
        _ = hold.update(.moveCloser, at: 0.5)

        let before = hold.update(.moreLight, at: 1)
        let after = hold.update(.moreLight, at: 1.5)

        #expect(before == .moveCloser)
        #expect(after == .moreLight)
    }
}
