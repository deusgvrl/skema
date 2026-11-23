//
//  ScanGuidance.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 12/11/26.
//

import Foundation
import MeasureKit

nonisolated enum ScanGuidance: Equatable, Sendable {

    case moreLight
    case moveCloser
    /// No floor yet after `ScanViewModel.floorWaitBeforeTip` seconds (A10-112). Set by the floor search, never by
    /// `guidance(tracking:ambientIntensity:depth:)`.
    case floorNotFound

    /// The centred instruction's line for this problem (copy approved 23 Nov 2026).
    var message: String {
        switch self {
        case .moreLight: "More light needed"
        case .moveCloser: "Move closer"
        case .floorNotFound: "Floor not found yet"
        }
    }

    /// The SF Symbol shown above the line while the camera dims (Measure's coaching look).
    var symbol: String {
        switch self {
        case .moreLight: "lightbulb.max.fill"
        case .moveCloser: "figure.walk"
        case .floorNotFound: "arrow.down.to.line"
        }
    }

    /// The small line under it, when there is one.
    var detail: String? {
        switch self {
        case .floorNotFound: "Tilt down and move closer to it"
        case .moreLight, .moveCloser: nil
        }
    }

    /// ARKit's light estimate is about 1000 in a lit room. Below this counts as dark.
    static let darkBelow: Float = 250
    /// When less than this share of the confident depth points is within range, the set is too far.
    static let minNearShare: Float = 0.1

    /// The tip for one frame, or nil when the scan is going well. A dark room comes first, whatever the tracking: in
    /// the dark, tracking keeps dropping to limited and back, and the tip must stay up through that instead of
    /// letting "Floor not found yet" or the step show in between. Otherwise there is a tip only while tracking is
    /// normal (when it is limited, Apple's coaching screen in `RoomScanView` shows instead, as in Measure), then
    /// distance.
    static func guidance(tracking: ScanTracking, ambientIntensity: Float?, depth: DepthFrame?) -> ScanGuidance? {
        if let ambientIntensity, ambientIntensity < darkBelow { return .moreLight }
        guard tracking == .normal else { return nil }
        if let depth, nearShare(of: depth) < minNearShare { return .moveCloser }
        return nil
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
