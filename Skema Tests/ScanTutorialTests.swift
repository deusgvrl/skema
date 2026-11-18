//
//  ScanTutorialTests.swift
//  Skema Tests
//
//  The 4-step tutorial before a scan: tap the product, show the floor, turn to each item, finish.
//  Users thought they had to walk around the whole set; the steps say otherwise.
//

import SwiftUI
import Testing
@testable import Final_Challenge_App

@Suite("Scan tutorial")
struct ScanTutorialTests {
    @Test("Four steps in the order the scan needs them")
    func order() {
        #expect(ScanTutorialStep.allCases.map(\.title) == [
            "Tap your product",
            "Show the floor",
            "Turn to each light and camera",
            "Tap Finish Scan"
        ])
    }

    @Test("The turning step says there's no need to walk around the set")
    func noWalkingAround() {
        #expect(ScanTutorialStep.turnToEachItem.message.contains("No need to walk around the set"))
        #expect(!ScanTutorialStep.allCases.contains { $0.message.localizedCaseInsensitiveContains("circle the subject") })
    }

    @Test("Every step but the last moves on; the last starts the scan", arguments: ScanTutorialStep.allCases)
    func primaryButton(step: ScanTutorialStep) {
        let isLast = step == ScanTutorialStep.allCases.last
        #expect(step.isLast == isLast)
        #expect(step.primaryButtonTitle == (isLast ? "Start Scanning" : "Next"))
        #expect(step.next == (isLast ? nil : ScanTutorialStep(rawValue: step.rawValue + 1)))
    }

    @Test("Each step reads its position for VoiceOver")
    func position() {
        #expect(ScanTutorialStep.tapSubject.positionLabel == "Step 1 of 4")
        #expect(ScanTutorialStep.finish.positionLabel == "Step 4 of 4")
    }
}
