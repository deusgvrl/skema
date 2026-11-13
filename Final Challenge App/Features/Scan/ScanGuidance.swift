//
//  ScanGuidance.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 12/11/26.
//

import Foundation
import MeasureKit

nonisolated enum ScanGuidance: Equatable, Sendable {

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

    /// ARKit's light estimate is about 1000 in a lit room. Below this counts as dark.
    static let darkBelow: Float = 250
    /// When less than this share of the confident depth points is within range, the set is too far.
    static let minNearShare: Float = 0.1

    /// The tip for one frame, or nil when the scan is going well.
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

    /// Share of the confident depth points (every 4th pixel) that are within `DepthSampler.maxRange`.
    /// 0 when there are no confident points at all.
    static func nearShare(of depth: DepthFrame) -> Float {
        let dots = DepthPreview.dots(from: depth)
        guard !dots.isEmpty else { return 0 }
        let near = dots.count { $0.depth <= DepthSampler.maxRange }
        return Float(near) / Float(dots.count)
    }
}

/// Keeps a tip from flickering: a new tip, or no tip, shows only after it held for `delay` seconds.
nonisolated struct GuidanceHold: Sendable {
    static let delay: TimeInterval = 0.5

    private(set) var shown: ScanGuidance?
    private var candidate: ScanGuidance?
    private var candidateSince: TimeInterval = 0

    /// The tip to show after this frame's tip at `time` (the frame's timestamp, in seconds).
    mutating func update(_ tip: ScanGuidance?, at time: TimeInterval) -> ScanGuidance? {
        if tip != candidate {
            candidate = tip
            candidateSince = time
        }
        // A small margin, so 0.1 s steps that add up to 0.5 s count as 0.5 s.
        if candidate != shown, time - candidateSince >= Self.delay - 0.000_001 {
            shown = candidate
        }
        return shown
    }
}
