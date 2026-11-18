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

    @Test("White button text (Recover) clears AA on an AccentPrimary fill")
    func whiteTextOnAccent() {
        #expect(contrastRatio(.white, DesignTokens.accentPrimary, style: .light) >= 4.5)
        #expect(contrastRatio(.white, DesignTokens.accentPrimary, style: .dark) >= 4.5)
    }

    @Test("Deleted-setup toast: message clears AA, bold Undo clears the large-text floor")
    func deletedToastContrast() {
        #expect(contrastRatio(.white, DesignTokens.toastBackground, style: .light) >= 4.5)
        #expect(contrastRatio(.white, DesignTokens.toastBackground, style: .dark) >= 4.5)
        #expect(contrastRatio(DesignTokens.accentPrimary, DesignTokens.toastBackground, style: .light) >= 3.0)
        #expect(contrastRatio(DesignTokens.accentPrimary, DesignTokens.toastBackground, style: .dark) >= 3.0)
    }

    @Test("Sheet text (title, step body, Don't Show Again) clears AA on SheetBackground",
          arguments: [UIUserInterfaceStyle.light, .dark])
    func sheetTextContrast(style: UIUserInterfaceStyle) {
        #expect(contrastRatio(DesignTokens.textPrimary, DesignTokens.sheetBackground, style: style) >= 4.5)
        #expect(contrastRatio(DesignTokens.textSecondary, DesignTokens.sheetBackground, style: style) >= 4.5)
        #expect(contrastRatio(DesignTokens.accentText, DesignTokens.sheetBackground, style: style) >= 4.5)
    }

    @Test("Add Equipment Manually link clears AA on the page background under its scrim",
          arguments: [UIUserInterfaceStyle.light, .dark])
    func accentTextOnPage(style: UIUserInterfaceStyle) {
        let backdrop = blended(Color("ScrimGradientBottom"), over: DesignTokens.pageBackground, style: style)
        #expect(contrastRatio(DesignTokens.accentText, DesignTokens.pageBackground, style: style) >= 4.5)
        #expect(contrastRatio(DesignTokens.accentText, backdrop, style: style) >= 4.5)
    }

    @Test("Diagram: node outlines clear 3:1, labels and distances clear AA on the canvas",
          arguments: [UIUserInterfaceStyle.light, .dark])
    func diagramContrast(style: UIUserInterfaceStyle) {
        #expect(contrastRatio(DesignTokens.diagramStroke, DesignTokens.pageBackground, style: style) >= 3.0)
        #expect(contrastRatio(DesignTokens.diagramStroke, DesignTokens.diagramNodeFill, style: style) >= 3.0)
        #expect(contrastRatio(DesignTokens.textPrimary, DesignTokens.pageBackground, style: style) >= 4.5)
        #expect(contrastRatio(DesignTokens.textSecondary, DesignTokens.pageBackground, style: style) >= 4.5)
        #expect(contrastRatio(DesignTokens.textPrimary, DesignTokens.diagramSubjectFill, style: style) >= 4.5)
    }

    @Test("Equipment sheet rows: label, value and red category clear AA on FormRowBackground",
          arguments: [UIUserInterfaceStyle.light, .dark])
    func formRowContrast(style: UIUserInterfaceStyle) {
        #expect(contrastRatio(DesignTokens.textPrimary, DesignTokens.formRowBackground, style: style) >= 4.5)
        #expect(contrastRatio(DesignTokens.textSecondary, DesignTokens.formRowBackground, style: style) >= 4.5)
        #expect(contrastRatio(DesignTokens.accentText, DesignTokens.formRowBackground, style: style) >= 4.5)
    }

    @Test("Detected green (tutorial ticks, captured items) clears 3:1 on the sheet and the canvas",
          arguments: [UIUserInterfaceStyle.light, .dark])
    func detectedGreenContrast(style: UIUserInterfaceStyle) {
        #expect(contrastRatio(DesignTokens.detectedGreen, DesignTokens.sheetBackground, style: style) >= 3.0)
        #expect(contrastRatio(DesignTokens.detectedGreen, DesignTokens.pageBackground, style: style) >= 3.0)
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
