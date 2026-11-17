//
//  DiagramEntity.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 17/11/26.
//
//  The subject on the diagram: a card with a figure and its title (Sketch R04 "Set / Table").
//

import SwiftUI

struct DiagramEntity: View {
    let title: String
    /// Kept for existing call sites; the Sketch card draws a figure instead of an SF Symbol.
    let icon: String
    let position: CGPoint
    var currentScale: CGFloat = 1.0
    var onTap: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5)
                .fill(DesignTokens.nodeDetailFill)
                .frame(width: 16, height: 26)
            Text(title)
                .font(.footnote)
                .foregroundStyle(DesignTokens.textPrimary)
                .fixedSize()
        }
        .frame(width: 104, height: 68)
        .background(DesignTokens.diagramSubjectFill, in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(DesignTokens.diagramSubjectBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
        .contentShape(.rect(cornerRadius: 10))
        .scaleEffect(1 / currentScale)
        .position(position)
        .onTapGesture {
            onTap()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    ZStack {
        DesignTokens.pageBackground
        DiagramEntity(
            title: "Subject",
            icon: "person.fill",
            position: CGPoint(x: 150, y: 150),
            currentScale: 1.0,
            onTap: {}
        )
    }
    .frame(width: 300, height: 300)
}
