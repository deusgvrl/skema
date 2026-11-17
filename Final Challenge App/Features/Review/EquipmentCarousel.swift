//
//  EquipmentCarousel.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 13/11/26.
//
//  Glass chips under the diagram, one per item ("L1 Key"); tapping opens its sheet (Sketch R04).
//

import SwiftUI

struct EquipmentCarousel: View {
    let viewModel: ReviewViewModel
    var isReadOnly: Bool = false
    var onNodeTap: ((Equipment) -> Void)?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(viewModel.chipOrder) { node in
                    Button {
                        onNodeTap?(node)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(DesignTokens.textSecondary)
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                            Text(node.displayName)
                                .font(.body)
                                .foregroundStyle(DesignTokens.textPrimary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .glassEffect(.regular.tint(DesignTokens.glassControlFill).interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .background(DesignTokens.pageBackground)
    }
}

#Preview {
    EquipmentCarousel(viewModel: ReviewViewModel())
}
