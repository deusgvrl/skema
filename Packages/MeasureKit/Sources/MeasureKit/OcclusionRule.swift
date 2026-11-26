//
//  OcclusionRule.swift
//  MeasureKit
//
//  Created by Amadeus Gavriel on 24/11/26.
//

import Foundation

/// Decides if a measure line is hidden by something real in front of it (design 5.4).
public enum OcclusionRule {
    /// The real scene must be this many metres closer than the line to hide it. Smaller gaps are depth noise.
    public static let margin: Float = 0.03

    /// Depth pixels with a lower confidence than this are not trusted (0 = low, 1 = medium, 2 = high).
    public static let minConfidence: UInt8 = 1

    /// Depth pixels farther than this many metres are not trusted. Same limit as the measure sampling.
    public static let maxRange: Float = DepthSampler.maxRange

    /// True when the real scene at this pixel is clearly in front of the line, so the line must be hidden.
    /// Missing depth (0, negative or NaN), low confidence and far depth never hide the line.
    public static func isHidden(lineDepth: Float, sceneDepth: Float, confidence: UInt8) -> Bool {
        guard sceneDepth.isFinite, sceneDepth > 0 else { return false }
        guard confidence >= minConfidence else { return false }
        guard sceneDepth <= maxRange else { return false }
        return sceneDepth < lineDepth - margin
    }
}
