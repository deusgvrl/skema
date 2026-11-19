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

    var body: some View {
        ZStack {
            // Subject Circle Shape (enlarged to 64x64)
            Circle()
                .fill(DesignTokens.accentPrimary)
                .frame(width: 64, height: 64)
                .overlay(
                    Circle()
                        .stroke(DesignTokens.diagramSubjectBorder, lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            
            // Title text centered inside the circle
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 6)
        }
        .frame(width: 64, height: 64)
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
