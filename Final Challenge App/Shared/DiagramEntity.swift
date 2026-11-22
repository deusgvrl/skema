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
    /// Kept to preserve backward compatibility with existing call sites
    var icon: String = ""
    let position: CGPoint
    var currentScale: CGFloat = 1.0
    var onTap: () -> Void

    @ScaledMetric(relativeTo: .caption) private var circleDimension: CGFloat = 64

    private var effectiveSize: CGFloat {
        min(max(circleDimension, 64), 84)
    }

    var body: some View {
        ZStack {
            // Subject Circle Shape (adapts with Dynamic Type)
            Circle()
                .fill(DesignTokens.accentPrimary)
                .frame(width: effectiveSize, height: effectiveSize)
                .overlay(
                    Circle()
                        .stroke(DesignTokens.diagramSubjectBorder, lineWidth: 1.5)
                )
                .overlay(
                    // Inner outline ring
                    Circle()
                        .stroke(Color.primary, lineWidth: 2)
                )
            // Title text centered inside the circle
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 6)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .frame(width: effectiveSize, height: effectiveSize)
        .contentShape(Circle())
        .scaleEffect(1 / currentScale)
        .position(position)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Subject")
        .accessibilityHint("Double tap to select or view details")
        .accessibilityAddTraits(.isButton)
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
