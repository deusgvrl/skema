//
//  ReviewDiagramContentView.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 13/11/26.
//

import SwiftUI
import TipKit

struct ReviewDiagramContentView: View {
    @Bindable var viewModel: ReviewViewModel
    var undoManager: UndoManager? = nil
    var isReadOnly: Bool = true
    
    var onNodeTap: (Equipment) -> Void
    var onSubjectTap: () -> Void
    var onAddNodeTap: () -> Void
    var onEditTap: () -> Void
    
    // TipKit Instance
    private let interactionTip = DiagramInteractionTip()
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                LightingDiagramView(
                    viewModel: viewModel,
                    isReadOnly: isReadOnly,
                    undoManager: undoManager,
                    onNodeTap: onNodeTap,
                    onSubjectTap: onSubjectTap
                )
                .overlay(alignment: .bottomTrailing) {
                    if isReadOnly {
                        Button {
                            onEditTap()
                        } label: {
                            Image(systemName: "pencil")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(Color.accentColor, in: .circle)
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        }
                        .accessibilityLabel("Edit Diagram")
                        .padding(16)
                    } else {
                        Button {
                            onAddNodeTap()
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(Color.accentColor, in: .circle)
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        }
                        .accessibilityLabel("Add Equipment")
                        .padding(16)
                    }
                }
                
                // Prominent TipKit Card Overlay - only in edit mode
                if !isReadOnly && !viewModel.nodes.isEmpty {
                    TipView(interactionTip, arrowEdge: .none)
                        .tipBackground(Color(uiColor: .secondarySystemGroupedBackground))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }
            }
            
            EquipmentCarousel(
                viewModel: viewModel,
                isReadOnly: isReadOnly,
                onNodeTap: onNodeTap
            )
        }
    }
}

struct DiagramInteractionTip: Tip {
    var title: Text {
        Text("Diagram Gestures")
    }
    
    var message: Text? {
        Text("Long press equipment icon to move or rotate. Tap to edit details.")
    }
    
    var image: Image? {
        Image(systemName: "hand.tap.fill")
    }
}

#Preview {
    ReviewDiagramContentView(
        viewModel: ReviewViewModel(),
        isReadOnly: true,
        onNodeTap: { _ in },
        onSubjectTap: {},
        onAddNodeTap: {},
        onEditTap: {}
    )
    .task {
        // Enables previewing TipKit cards inside Xcode Canvas
        try? Tips.resetDatastore()
        try? Tips.configure([.displayFrequency(.immediate)])
    }
}
