//
//  ScanGuideSettings.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 08/11/26.
//
//  Whether the in-scan tutorial was finished or skipped (Sketch UT Review T01–T10): it shows on the first scan only,
//  and the ? on the scan screen replays it.
//

import Foundation

/// UserDefaults is safe from any thread, so this needs no actor (ScanView makes one as a default argument).
nonisolated struct ScanGuideSettings {
    /// A new key: the old "Before You Scan" sheet's choice does not hide the new tutorial.
    private static let doneKey = "scanTutorial.isDone"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isTutorialDone: Bool {
        get { defaults.bool(forKey: Self.doneKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.doneKey) }
    }
}
