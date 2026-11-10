//
//  FrameThrottle.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 10/11/26.
//

import Foundation
nonisolated struct FrameThrottle {

    private static let tolerance: TimeInterval = 0.001

    let minimumInterval: TimeInterval
    private var lastAccepted: TimeInterval?

    init(minimumInterval: TimeInterval) {
        self.minimumInterval = minimumInterval
    }

    mutating func accepts(_ timestamp: TimeInterval) -> Bool {
        if let lastAccepted, timestamp - lastAccepted + Self.tolerance < minimumInterval {
            return false
        }
        lastAccepted = timestamp
        return true
    }
}
