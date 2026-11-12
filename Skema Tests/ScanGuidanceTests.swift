//
//  ScanGuidanceTests.swift
//  Skema Tests
//
//  Created by Muhammad Dzakki Abdullah on 12/11/26.
//

import Foundation
import MeasureKit
import Testing
import UIKit
@testable import Final_Challenge_App

@Suite("Scan guidance: tips when the scan goes badly")
struct ScanGuidanceTests {

    let near = makeDepth(width: 8, height: 8, depth: 1)
    let far = makeDepth(width: 8, height: 8, depth: 6)

    @Test("Each tracking problem has its tip", arguments: [
        (ScanTracking.limited(.initializing), ScanGuidance?.some(.keepMoving)),
        (.limited(.excessiveMotion), .moveSlower),
        (.limited(.relocalizing), .goBack),
        (.limited(.insufficientFeatures), .aimAtDetail),
        (.limited(.other), nil),
        (.notAvailable, nil),
        (.normal, nil)
    ])
    func tracking(tracking: ScanTracking, expected: ScanGuidance?) {
        let tip = ScanGuidance.guidance(tracking: tracking, ambientIntensity: 1000, depth: near)

        #expect(tip == expected)
    }

    @Test("A dark room asks for more light", arguments: [ScanTracking.normal, .limited(.insufficientFeatures)])
    func dark(tracking: ScanTracking) {
        let tip = ScanGuidance.guidance(tracking: tracking, ambientIntensity: 100, depth: near)

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

    @Test("Moving too fast wins over dark and far")
    func priority() {
        let tip = ScanGuidance.guidance(tracking: .limited(.excessiveMotion), ambientIntensity: 100, depth: far)

        #expect(tip == .moveSlower)
    }

    @Test("The tips from the Jira story read as written", arguments: [
        (ScanGuidance.moveSlower, "Move slower"),
        (.moreLight, "More light"),
        (.moveCloser, "Move closer")
    ])
    func messages(tip: ScanGuidance, expected: String) {
        #expect(tip.message == expected)
    }

    @Test("Every tip's symbol exists", arguments: ScanGuidance.allCases)
    func symbols(tip: ScanGuidance) {
        #expect(UIImage(systemName: tip.systemImage) != nil)
    }
}

@Suite("Guidance hold: tips do not flicker")
struct GuidanceHoldTests {
    @Test("A tip shows after it held for 0.5 s")
    func showsAfterHold() {
        var hold = GuidanceHold()

        let early = hold.update(.moveSlower, at: 0)
        let stillEarly = hold.update(.moveSlower, at: 0.4)
        let shown = hold.update(.moveSlower, at: 0.5)

        #expect(early == nil)
        #expect(stillEarly == nil)
        #expect(shown == .moveSlower)
    }

    @Test("The tip goes 0.5 s after tracking recovers")
    func hidesAfterRecovery() {
        var hold = GuidanceHold()
        _ = hold.update(.moveSlower, at: 0)
        _ = hold.update(.moveSlower, at: 0.5)

        let stillShown = hold.update(nil, at: 1.0)
        let hidden = hold.update(nil, at: 1.5)

        #expect(stillShown == .moveSlower)
        #expect(hidden == nil)
    }

    @Test("A problem shorter than 0.5 s never shows")
    func briefProblemIgnored() {
        var hold = GuidanceHold()

        _ = hold.update(.moveSlower, at: 0)
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
        _ = hold.update(.moveSlower, at: 0)
        _ = hold.update(.moveSlower, at: 0.5)

        let before = hold.update(.moreLight, at: 1)
        let after = hold.update(.moreLight, at: 1.5)

        #expect(before == .moveSlower)
        #expect(after == .moreLight)
    }
}
