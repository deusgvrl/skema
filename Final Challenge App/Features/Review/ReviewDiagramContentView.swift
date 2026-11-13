//
//  ReviewDiagramContentView.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 13/11/26.
//

import SwiftUI

struct ReviewDiagramContentView: View {
    @Bindable var viewModel: ReviewViewModel
    var undoManager: UndoManager?
    
    var onNodeTap: (Equipment) -> Void
    var onSubjectTap: () -> Void
    var onAddNodeTap: () -> Void
    
    @State private var showHint = true
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                LightingDiagramView(
                    viewModel: viewModel,
                    isReadOnly: false,
                    undoManager: undoManager,
                    onNodeTap: onNodeTap,
                    onSubjectTap: onSubjectTap
                )
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        onAddNodeTap()
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Color.gray, in: .circle)
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    }
                    .padding(16)
                }
                
                if showHint && !viewModel.nodes.isEmpty {
                    HStack {
                        Text("Long press to move/rotate, or tap to edit details")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Button {
                            withAnimation { showHint = false }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color(uiColor: .systemBackground))
                            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            
            EquipmentCarousel(
                viewModel: viewModel,
                isReadOnly: false,
                onNodeTap: onNodeTap
            )
        }
    }
}

#Preview {
    ReviewDiagramContentView(viewModel: ReviewViewModel(), onNodeTap: {_ in }, onSubjectTap: {}, onAddNodeTap: {})
}
