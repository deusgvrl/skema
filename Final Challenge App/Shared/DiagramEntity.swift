//
//  DiagramEntity.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 17/11/26.
//

import SwiftUI

struct DiagramEntity: View {
    let title: String
    let icon: String
    let position: CGPoint
    var currentScale: CGFloat = 1.0
    var onTap: () -> Void
    
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(DesignTokens.glassCardFill)
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .font(.title3)
            )
            .overlay(alignment: .bottom) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(y: 20)
            }
            .scaleEffect(1 / currentScale)
            .position(position)
            .onTapGesture {
                onTap()
            }
    }
}


#Preview {
    ZStack {
        DiagramEntity(
            title: "Subject",
            icon: "person.fill",
            position: CGPoint(x: 150, y: 150),
            currentScale: 1.0,
            onTap: {
                print("Subject tapped in preview")
            }
        )
    }
    .frame(width: 300, height: 300)
    .background(Color(uiColor: .systemGroupedBackground))
}
