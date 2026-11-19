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
    /// SF Symbol icon displayed inside the circle (defaults to "person.fill").
    let icon: String
    let position: CGPoint
    var currentScale: CGFloat = 1.0
    var onTap: () -> Void

    var body: some View {
        ZStack {
            // Subject Circle Shape
            Circle()
                .fill(DesignTokens.diagramSubjectFill)
                .frame(width: 44, height: 44)
                .overlay(
                    Circle()
                        .stroke(DesignTokens.diagramSubjectBorder, lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                .overlay(
                    Image(systemName: icon.isEmpty ? "person.fill" : icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(DesignTokens.textPrimary)
                )
        }
        .frame(width: 44, height: 44)
        // Title text positioned cleanly below the circle
        .overlay(alignment: .bottom) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
                .fixedSize()
                .offset(y: 20)
        }
        .contentShape(Circle())
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
