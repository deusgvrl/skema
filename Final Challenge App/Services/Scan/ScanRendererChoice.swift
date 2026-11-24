//
//  ScanRendererChoice.swift
//  Final Challenge App
//
//  Created by Amadeus Gavriel on 24/11/26.
//
//  Which camera view the scan screen uses: ARView (RealityKit) or our own Metal view.
//  A launch argument can change it, for example "-scanRenderer metal", so we can compare the cost.
//

import Foundation

/// UserDefaults is safe from any thread, so this needs no actor.
nonisolated enum ScanRendererChoice: Equatable, Sendable {
    /// The RealityKit ARView. This is the default.
    case arView
    /// Our own Metal view.
    case metal

    static let key = "scanRenderer"

    /// Reads the choice. The value "metal" (any letter case) gives `.metal`.
    /// A missing key, or any other value, gives `.arView`.
    init(defaults: UserDefaults) {
        if defaults.string(forKey: Self.key)?.lowercased() == "metal" {
            self = .metal
        } else {
            self = .arView
        }
    }
}
