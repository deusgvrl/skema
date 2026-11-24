//
//  OcclusionRuleTests.swift
//  MeasureKitTests
//
//  Created by Amadeus Gavriel on 24/11/26.
//

import Testing
@testable import MeasureKit

/// Design 5.4: a measure line is hidden only where the real scene is clearly in front of it.
@Suite("Occlusion rule")
struct OcclusionRuleTests {
    @Test("M9: a wall 0.5 m in front of the line hides it")
    func sceneInFrontHides() {
        #expect(OcclusionRule.isHidden(lineDepth: 2.0, sceneDepth: 1.5, confidence: 2))
    }

    @Test("M10: a wall behind the line shows it")
    func sceneBehindShows() {
        #expect(!OcclusionRule.isHidden(lineDepth: 2.0, sceneDepth: 2.5, confidence: 2))
    }

    @Test("M11: a 1 cm difference is noise, the line shows")
    func smallDifferenceShows() {
        #expect(!OcclusionRule.isHidden(lineDepth: 2.0, sceneDepth: 1.99, confidence: 2))
    }

    @Test("M12: no depth (0 or NaN) shows the line")
    func missingDepthShows() {
        #expect(!OcclusionRule.isHidden(lineDepth: 2.0, sceneDepth: 0, confidence: 2))
        #expect(!OcclusionRule.isHidden(lineDepth: 2.0, sceneDepth: .nan, confidence: 2))
    }

    @Test("M13: low confidence shows the line")
    func lowConfidenceShows() {
        #expect(!OcclusionRule.isHidden(lineDepth: 2.0, sceneDepth: 1.0, confidence: 0))
    }

    @Test("M13a: depth beyond the max range shows the line")
    func beyondRangeShows() {
        #expect(!OcclusionRule.isHidden(lineDepth: 6.0, sceneDepth: 5.5, confidence: 2))
    }

    @Test("The 3 cm edge: just past it hides, just inside it shows")
    func marginEdge() {
        #expect(OcclusionRule.isHidden(lineDepth: 2.0, sceneDepth: 1.969, confidence: 2))
        #expect(!OcclusionRule.isHidden(lineDepth: 2.0, sceneDepth: 1.971, confidence: 2))
    }
}
