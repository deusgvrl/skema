//
//  ScanRendererChoiceTests.swift
//  Skema Tests
//
//  Created by Amadeus Gavriel on 24/11/26.
//

import Foundation
import Testing
@testable import Skema_Photo

@Suite("Scan renderer choice")
struct ScanRendererChoiceTests {
    /// A fresh, empty UserDefaults suite. The test removes it when it ends.
    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "ScanRendererChoiceTests.\(UUID())"
        // Force unwrap is fine: a suite name that is not the app's own bundle id always works.
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    @Test("M1: no key gives the ARView renderer")
    func noKeyGivesTheARViewRenderer() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(ScanRendererChoice(defaults: defaults) == .arView)
    }

    @Test("M2: the value metal gives the Metal renderer")
    func metalValueGivesTheMetalRenderer() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // A launch argument such as "-scanRenderer metal" reaches UserDefaults as a string.
        defaults.set("metal", forKey: ScanRendererChoice.key)

        #expect(ScanRendererChoice(defaults: defaults) == .metal)
    }

    @Test("M3: a value that is not known gives the ARView renderer")
    func unknownValueGivesTheARViewRenderer() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("metl", forKey: ScanRendererChoice.key)

        #expect(ScanRendererChoice(defaults: defaults) == .arView)
    }

    @Test("M4: the value is read in any letter case")
    func valueIsReadInAnyLetterCase() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("METAL", forKey: ScanRendererChoice.key)

        #expect(ScanRendererChoice(defaults: defaults) == .metal)
    }
}
