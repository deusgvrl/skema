//
//  ContrastRatio.swift
//  Final Challenge App
//
//  WCAG 2.x relative-luminance contrast math for the design-token colors.
//

import SwiftUI

private struct RGBAComponents {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

private func resolvedRGBA(_ color: Color, style: UIUserInterfaceStyle) -> RGBAComponents {
    let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    var redComponent: CGFloat = 0, greenComponent: CGFloat = 0, blueComponent: CGFloat = 0, alphaComponent: CGFloat = 0
    resolved.getRed(&redComponent, green: &greenComponent, blue: &blueComponent, alpha: &alphaComponent)
    return RGBAComponents(
        red: Double(redComponent),
        green: Double(greenComponent),
        blue: Double(blueComponent),
        alpha: Double(alphaComponent)
    )
}

private func linearize(_ channel: Double) -> Double {
    channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
}

func relativeLuminance(_ color: Color, style: UIUserInterfaceStyle) -> Double {
    let components = resolvedRGBA(color, style: style)
    let red = linearize(components.red)
    let green = linearize(components.green)
    let blue = linearize(components.blue)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue
}

/// Ignores alpha on both inputs. A translucent `background` (a glass token) must be
/// composited with `blended(_:over:style:)` onto its real backdrop first, or this
/// silently measures against the token's raw color instead of what actually renders.
func contrastRatio(_ foreground: Color, _ background: Color, style: UIUserInterfaceStyle) -> Double {
    let foregroundLuminance = relativeLuminance(foreground, style: style)
    let backgroundLuminance = relativeLuminance(background, style: style)
    let lighter = max(foregroundLuminance, backgroundLuminance)
    let darker = min(foregroundLuminance, backgroundLuminance)
    return (lighter + 0.05) / (darker + 0.05)
}

func blended(_ foreground: Color, over background: Color, style: UIUserInterfaceStyle) -> Color {
    let foregroundComponents = resolvedRGBA(foreground, style: style)
    let backgroundComponents = resolvedRGBA(background, style: style)
    let alpha = foregroundComponents.alpha
    let red = foregroundComponents.red * alpha + backgroundComponents.red * (1 - alpha)
    let green = foregroundComponents.green * alpha + backgroundComponents.green * (1 - alpha)
    let blue = foregroundComponents.blue * alpha + backgroundComponents.blue * (1 - alpha)
    return Color(red: red, green: green, blue: blue)
}
