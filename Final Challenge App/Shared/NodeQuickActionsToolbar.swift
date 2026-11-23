//
//  NodeQuickActionToolbar.swift
//  Skema Photo
//
//  Created by Satriya Handha Wibowo on 23/11/26.
//

import SwiftUI

struct NodeQuickActionsToolbar: View {
    let nodeId: UUID
    var onDelete: (UUID) -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(role: .destructive) {
                onDelete(nodeId)
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}
