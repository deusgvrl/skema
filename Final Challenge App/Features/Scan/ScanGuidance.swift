//
//  ScanGuidance.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 12/11/26.
//

import Foundation
import MeasureKit

nonisolated enum ScanGuidance: CaseIterable, Equatable, Sendable {
    case keepMoving
    case moveSlower
    case moreLight
    case moveCloser
    case aimAtDetail
    case goBack

    var message: String {
        switch self {
        case .keepMoving: "Move your iPhone slowly to start"
        case .moveSlower: "Move slower"
        case .moreLight: "More light"
        case .moveCloser: "Move closer"
        case .aimAtDetail: "Point at the set, not a blank wall"
        case .goBack: "Point back where you were"
        }
    }

    var systemImage: String {
        switch self {
        case .keepMoving: "move.3d"
        case .moveSlower: "tortoise"
        case .moreLight: "lightbulb"
        case .moveCloser: "figure.walk"
        case .aimAtDetail: "viewfinder"
        case .goBack: "arrow.uturn.backward"
        }
    }

    /// ARKit's light estimate is about 1000 in a lit room. Below this counts as dark.
    static let darkBelow: Float = 250
    static let minNearShare: Float = 0.1

    /// Tracking problems come first, then light, then distance.
    static func guidance(tracking: ScanTracking, ambientIntensity: Float?, depth: DepthFrame?) -> ScanGuidance? {
        let isDark = ambientIntensity.map { $0 < darkBelow } ?? false
        switch tracking {
        case .limited(.initializing):
            return .keepMoving
        case .limited(.excessiveMotion):
            return .moveSlower
        case .limited(.relocalizing):
            return .goBack
        case .limited(.insufficientFeatures):
            return isDark ? .moreLight : .aimAtDetail
        case .limited(.other), .notAvailable:
            return nil
        case .normal:
            if isDark { return .moreLight }
            if let depth, nearShare(of: depth) < minNearShare { return .moveCloser }
            return nil
        }
    }

    static func nearShare(of depth: DepthFrame) -> Float {
        let dots = DepthPreview.dots(from: depth)
        guard !dots.isEmpty else { return 0 }
        let near = dots.count { $0.depth <= DepthSampler.maxRange }
        return Float(near) / Float(dots.count)
    }
}

nonisolated struct GuidanceHold: Sendable {
    static let delay: TimeInterval = 0.5

    private(set) var shown: ScanGuidance?
    private var candidate: ScanGuidance?
    private var candidateSince: TimeInterval = 0

    mutating func update(_ tip: ScanGuidance?, at time: TimeInterval) -> ScanGuidance? {
        if tip != candidate {
            candidate = tip
            candidateSince = time
        }
        if candidate != shown, time - candidateSince >= Self.delay - 0.000_001 {
            shown = candidate
        }
        return shown
    }
}
