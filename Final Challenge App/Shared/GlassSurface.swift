//
//  GlassSurface.swift
//  Final Challenge App
//
//  Reusable "Liquid Glass" surfaces built on the native iOS 27 glass material,
//  tinted with the design tokens extracted from Sketch HE Copy 2.
//

import SwiftUI

extension View {
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        self.glassEffect(.regular.tint(DesignTokens.glassCardFill), in: .rect(cornerRadius: cornerRadius))
    }

    func glassControl(cornerRadius: CGFloat = 24) -> some View {
        self.glassEffect(.regular.tint(DesignTokens.glassControlFill), in: .rect(cornerRadius: cornerRadius))
    }
}
