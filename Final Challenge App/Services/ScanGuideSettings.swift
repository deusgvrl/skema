//
//  ScanGuideSettings.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 08/11/26.
//

import Foundation

@MainActor  
struct ScanGuideSettings {
    private static let hiddenKey = "scanGuide.isHidden"
    private let defaults: UserDefaults

    init (defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isHidden: Bool {
        get { defaults.bool(forKey: Self.hiddenKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.hiddenKey) }
    }
}
