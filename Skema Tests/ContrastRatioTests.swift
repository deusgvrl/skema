//
//  ContrastRatioTests.swift
//  Skema Tests
//

import Testing
import SwiftUI
@testable import Final_Challenge_App

@Suite("WCAG AA contrast on the real token pairs")
struct ContrastRatioTests {
    @Test("Primary text clears AA on the glass card, both appearances")
    func textPrimaryOnCard() {
        #expect(contrastRatio(DesignTokens.textPrimary, DesignTokens.glassCardFill, style: .dark) >= 4.5)
        #expect(contrastRatio(DesignTokens.textPrimary, DesignTokens.glassCardFill, style: .light) >= 4.5)
    }

    @Test("Secondary text clears AA on the glass card, both appearances")
    func textSecondaryOnCard() {
        #expect(contrastRatio(DesignTokens.textSecondary, DesignTokens.glassCardFill, style: .dark) >= 4.5)
        #expect(contrastRatio(DesignTokens.textSecondary, DesignTokens.glassCardFill, style: .light) >= 4.5)
    }

    @Test("Title text on the raw scrim still clears AA against a worst-case bright/dark cover photo")
    func titleOnScrimWorstCasePhoto() {
        let worstPhotoDark = Color.white
        let worstPhotoLight = Color.black
        let darkBackdrop = blended(Color("ScrimGradientTop"), over: worstPhotoDark, style: .dark)
        let lightBackdrop = blended(Color("ScrimGradientTop"), over: worstPhotoLight, style: .light)
        #expect(contrastRatio(DesignTokens.textPrimary, darkBackdrop, style: .dark) >= 4.5)
        #expect(contrastRatio(DesignTokens.textPrimary, lightBackdrop, style: .light) >= 4.5)
    }

    @Test("White FAB icon clears the 3:1 UI-component floor on AccentPrimary")
    func fabIconOnAccent() {
        #expect(contrastRatio(.white, DesignTokens.accentPrimary, style: .dark) >= 3.0)
    }
}
