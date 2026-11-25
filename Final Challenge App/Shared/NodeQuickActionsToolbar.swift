//
//  NodeQuickActionToolbar.swift
//  Skema Photo
//
//  Created by Satriya Handha Wibowo on 23/11/26.
//

import SwiftUI

struct NodeQuickActionsToolbar: View {
    let nodeId: UUID?
    var showsDelete: Bool = true
    var onDelete: ((UUID) -> Void)?
    var onAdd: () -> Void

    var body: some View {
        HStack {
            // Delete Button (Visible only when editing equipment nodes)
            if showsDelete, let id = nodeId {
                Button(role: .destructive) {
                    onDelete?(id)
                } label: {
                    Image(systemName: "trash")
                        .font(.title2)
                        .foregroundStyle(.red)
                        .frame(width: 45, height: 45)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Delete")
                .glassEffect(.clear.interactive())
            }

            Spacer()

            // Right-aligned Plus Button (45x45)
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 45, height: 45)
                    .background(Circle().fill(DesignTokens.accentPrimary))
            }
            .glassEffect(.clear.interactive())
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity)
    }
}
