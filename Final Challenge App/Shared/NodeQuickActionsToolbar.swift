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

    var body: some View {
        HStack {
            Spacer()
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
                .glassEffect(.clear.interactive())
            }

            Spacer()
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity)
    }
}
