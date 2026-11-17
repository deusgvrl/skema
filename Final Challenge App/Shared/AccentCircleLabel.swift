//
//  AccentCircleLabel.swift
//  Final Challenge App
//
//  The red floating circle used for the pencil (Sketch R04, R08) and the References + (R11).
//  A label, so it works as a Button label or a Menu label.
//

import SwiftUI

struct AccentCircleLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .font(.title3.weight(.medium))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(DesignTokens.accentPrimary, in: .circle)
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            .contentShape(.circle)
    }
}

#Preview {
    AccentCircleLabel(title: "Edit Diagram", systemImage: "pencil")
        .padding()
}
