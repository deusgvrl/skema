//
//  DesignTokensTests.swift
//  Skema Tests
//

import Testing
import SwiftUI
@testable import Final_Challenge_App

struct ResolvedRGBA {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

func resolvedComponents(_ color: Color, style: UIUserInterfaceStyle) -> ResolvedRGBA {
    let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return ResolvedRGBA(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha))
}

@Suite("Design tokens resolve to the exact extracted Sketch values")
struct DesignTokensTests {
    @Test("AccentPrimary is identical in light and dark")
    func accentPrimary() {
        let light = resolvedComponents(DesignTokens.accentPrimary, style: .light)
        let dark = resolvedComponents(DesignTokens.accentPrimary, style: .dark)
        #expect(abs(light.red - 0.784) < 0.01 && abs(light.green - 0.157) < 0.01 && abs(light.blue - 0.102) < 0.01)
        #expect(abs(dark.red - 0.784) < 0.01 && abs(dark.green - 0.157) < 0.01 && abs(dark.blue - 0.102) < 0.01)
    }

    @Test("TextPrimary differs light vs dark", arguments: [
        (UIUserInterfaceStyle.light, ResolvedRGBA(red: 0.067, green: 0.067, blue: 0.075, alpha: 1.0)),
        (.dark, ResolvedRGBA(red: 0.961, green: 0.961, blue: 0.969, alpha: 1.0))
    ])
    func textPrimary(style: UIUserInterfaceStyle, expected: ResolvedRGBA) {
        let resolved = resolvedComponents(DesignTokens.textPrimary, style: style)
        #expect(abs(resolved.red - expected.red) < 0.01)
        #expect(abs(resolved.green - expected.green) < 0.01)
        #expect(abs(resolved.blue - expected.blue) < 0.01)
    }

    @Test("TextSecondary differs light vs dark, dark uses the contrast-safe value", arguments: [
        (UIUserInterfaceStyle.light, ResolvedRGBA(red: 0.365, green: 0.365, blue: 0.388, alpha: 1.0)),
        (.dark, ResolvedRGBA(red: 0.675, green: 0.675, blue: 0.694, alpha: 1.0))
    ])
    func textSecondary(style: UIUserInterfaceStyle, expected: ResolvedRGBA) {
        let resolved = resolvedComponents(DesignTokens.textSecondary, style: style)
        #expect(abs(resolved.red - expected.red) < 0.01)
        #expect(abs(resolved.green - expected.green) < 0.01)
        #expect(abs(resolved.blue - expected.blue) < 0.01)
    }

    @Test("GlassCardFill has the right fill and alpha per appearance", arguments: [
        (UIUserInterfaceStyle.light, ResolvedRGBA(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.722)),
        (.dark, ResolvedRGBA(red: 0.224, green: 0.239, blue: 0.263, alpha: 0.920))
    ])
    func glassCardFill(style: UIUserInterfaceStyle, expected: ResolvedRGBA) {
        let resolved = resolvedComponents(DesignTokens.glassCardFill, style: style)
        #expect(abs(resolved.red - expected.red) < 0.01)
        #expect(abs(resolved.green - expected.green) < 0.01)
        #expect(abs(resolved.blue - expected.blue) < 0.01)
        #expect(abs(resolved.alpha - expected.alpha) < 0.01)
    }

    @Test("PageBackground differs light vs dark", arguments: [
        (UIUserInterfaceStyle.light, ResolvedRGBA(red: 0.957, green: 0.953, blue: 0.945, alpha: 1.0)),
        (.dark, ResolvedRGBA(red: 0.055, green: 0.055, blue: 0.059, alpha: 1.0))
    ])
    func pageBackground(style: UIUserInterfaceStyle, expected: ResolvedRGBA) {
        let resolved = resolvedComponents(DesignTokens.pageBackground, style: style)
        #expect(abs(resolved.red - expected.red) < 0.01)
        #expect(abs(resolved.green - expected.green) < 0.01)
        #expect(abs(resolved.blue - expected.blue) < 0.01)
    }

    @Test("AccentText is the brand red in light and Sketch's lighter red in dark", arguments: [
        (UIUserInterfaceStyle.light, ResolvedRGBA(red: 0.784, green: 0.157, blue: 0.102, alpha: 1.0)),
        (.dark, ResolvedRGBA(red: 1.0, green: 0.353, blue: 0.290, alpha: 1.0))
    ])
    func accentText(style: UIUserInterfaceStyle, expected: ResolvedRGBA) {
        let resolved = resolvedComponents(DesignTokens.accentText, style: style)
        #expect(abs(resolved.red - expected.red) < 0.01)
        #expect(abs(resolved.green - expected.green) < 0.01)
        #expect(abs(resolved.blue - expected.blue) < 0.01)
    }

    @Test("SheetBackground is opaque and differs light vs dark", arguments: [
        (UIUserInterfaceStyle.light, ResolvedRGBA(red: 0.961, green: 0.961, blue: 0.969, alpha: 1.0)),
        (.dark, ResolvedRGBA(red: 0.137, green: 0.141, blue: 0.157, alpha: 1.0))
    ])
    func sheetBackground(style: UIUserInterfaceStyle, expected: ResolvedRGBA) {
        let resolved = resolvedComponents(DesignTokens.sheetBackground, style: style)
        #expect(abs(resolved.red - expected.red) < 0.01)
        #expect(abs(resolved.green - expected.green) < 0.01)
        #expect(abs(resolved.blue - expected.blue) < 0.01)
        #expect(abs(resolved.alpha - expected.alpha) < 0.01)
    }

    @Test("NodeDetailFill is opaque and legible against both the canvas and the node body", arguments: [
        (UIUserInterfaceStyle.light, ResolvedRGBA(red: 0.333, green: 0.333, blue: 0.353, alpha: 1.0)),
        (.dark, ResolvedRGBA(red: 0.557, green: 0.557, blue: 0.576, alpha: 1.0))
    ])
    func nodeDetailFill(style: UIUserInterfaceStyle, expected: ResolvedRGBA) {
        let resolved = resolvedComponents(DesignTokens.nodeDetailFill, style: style)
        #expect(abs(resolved.red - expected.red) < 0.01)
        #expect(abs(resolved.green - expected.green) < 0.01)
        #expect(abs(resolved.blue - expected.blue) < 0.01)
        #expect(abs(resolved.alpha - expected.alpha) < 0.01)
    }

    @Test("Every remaining token has a dark entry distinct from its light one", arguments: [
        ("GlassCardBorder", UIUserInterfaceStyle.light, ResolvedRGBA(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.902)),
        ("GlassCardBorder", .dark, ResolvedRGBA(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.122)),
        ("GlassControlFill", .light, ResolvedRGBA(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.722)),
        ("GlassControlFill", .dark, ResolvedRGBA(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.122)),
        ("GlassControlBorderTop", .light, ResolvedRGBA(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)),
        ("GlassControlBorderTop", .dark, ResolvedRGBA(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.302)),
        ("GlassControlBorderBottom", .light, ResolvedRGBA(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.102)),
        ("GlassControlBorderBottom", .dark, ResolvedRGBA(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.400)),
        ("ScrimGradientTop", .light, ResolvedRGBA(red: 0.957, green: 0.953, blue: 0.945, alpha: 0.651)),
        ("ScrimGradientTop", .dark, ResolvedRGBA(red: 0.055, green: 0.055, blue: 0.059, alpha: 0.650)),
        ("ScrimGradientMid", .light, ResolvedRGBA(red: 0.957, green: 0.953, blue: 0.945, alpha: 0.820)),
        ("ScrimGradientMid", .dark, ResolvedRGBA(red: 0.055, green: 0.055, blue: 0.059, alpha: 0.651)),
        ("ScrimGradientBottom", .light, ResolvedRGBA(red: 0.957, green: 0.953, blue: 0.945, alpha: 0.949)),
        ("ScrimGradientBottom", .dark, ResolvedRGBA(red: 0.055, green: 0.055, blue: 0.059, alpha: 0.902))
    ])
    func remainingTokens(name: String, style: UIUserInterfaceStyle, expected: ResolvedRGBA) {
        let resolved = resolvedComponents(Color(name), style: style)
        #expect(abs(resolved.red - expected.red) < 0.01)
        #expect(abs(resolved.green - expected.green) < 0.01)
        #expect(abs(resolved.blue - expected.blue) < 0.01)
        #expect(abs(resolved.alpha - expected.alpha) < 0.01)
    }
}
