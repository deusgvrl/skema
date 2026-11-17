//
//  ContrastRatioTests.swift
//  Skema Tests
//

import Testing
import SwiftUI
@testable import Final_Challenge_App

private func worstCaseCardBackdrop(style: UIUserInterfaceStyle) -> Color {
    let worstPhoto: Color = style == .dark ? .white : .black
    let scrimOverPhoto = blended(Color("ScrimGradientTop"), over: worstPhoto, style: style)
    return blended(DesignTokens.glassCardFill, over: scrimOverPhoto, style: style)
}

@Suite("WCAG AA contrast on the real token pairs")
struct ContrastRatioTests {
    @Test("Primary text clears AA on the glass card, composited over the scrim and a worst-case cover photo")
    func textPrimaryOnCard() {
        #expect(contrastRatio(DesignTokens.textPrimary, worstCaseCardBackdrop(style: .dark), style: .dark) >= 4.5)
        #expect(contrastRatio(DesignTokens.textPrimary, worstCaseCardBackdrop(style: .light), style: .light) >= 4.5)
    }

    @Test("Secondary text clears AA on the glass card, composited over the scrim and a worst-case cover photo")
    func textSecondaryOnCard() {
        #expect(contrastRatio(DesignTokens.textSecondary, worstCaseCardBackdrop(style: .dark), style: .dark) >= 4.5)
        #expect(contrastRatio(DesignTokens.textSecondary, worstCaseCardBackdrop(style: .light), style: .light) >= 4.5)
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

    @Test("NodeDetailFill clears the 3:1 UI-component floor against the canvas and the node body")
    func nodeDetailFillContrast() {
        let systemBackground = Color(uiColor: .systemBackground)
        let systemGray5 = Color(uiColor: .systemGray5)
        #expect(contrastRatio(DesignTokens.nodeDetailFill, systemBackground, style: .light) >= 3.0)
        #expect(contrastRatio(DesignTokens.nodeDetailFill, systemBackground, style: .dark) >= 3.0)
        #expect(contrastRatio(DesignTokens.nodeDetailFill, systemGray5, style: .light) >= 3.0)
        #expect(contrastRatio(DesignTokens.nodeDetailFill, systemGray5, style: .dark) >= 3.0)
    }
}
