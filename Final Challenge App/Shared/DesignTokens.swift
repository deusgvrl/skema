//
//  DesignTokens.swift
//  Final Challenge App
//

import SwiftUI

enum DesignTokens {
    static let accentPrimary = Color("AccentPrimary")
    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
    static let glassCardFill = Color("GlassCardFill")
    static let nodeDetailFill = Color("NodeDetailFill")
    static let pageBackground = Color("PageBackground")
    /// A fixed dark chip in both appearances, like the Sketch R01v toast.
    static let toastBackground = Color.black
    static let glassCardBorder = Color("GlassCardBorder")
    static let glassControlFill = Color("GlassControlFill")
    static let glassControlBorderTop = Color("GlassControlBorderTop")
    static let glassControlBorderBottom = Color("GlassControlBorderBottom")

    static var scrimGradient: LinearGradient {
        LinearGradient(
            colors: [Color("ScrimGradientTop"), Color("ScrimGradientMid"), Color("ScrimGradientBottom")],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
