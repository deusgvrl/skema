//
//  SetupDetailSheetView.swift
//  Skema Photo
//
//  Created by Satriya Handha Wibowo on 23/11/26.
//

import SwiftUI

/// Shared bottom sheet container for editing equipment nodes or subject details on the diagram canvas.
struct DiagramSheetView: View {
    let activeSheetContent: DiagramSheetContent?
    let reviewViewModel: ReviewViewModel
    let isEditing: Bool
    let undoManager: UndoManager?
    @Binding var selectedDetent: PresentationDetent
    @Binding var currentSheetHeight: CGFloat

    var body: some View {
        Group {
            switch activeSheetContent {
            case .equipment(let nodeId):
                EquipmentFormView(
                    viewModel: reviewViewModel,
                    editingNodeId: nodeId,
                    undoManager: isEditing ? undoManager : nil,
                    isReadOnly: !isEditing,
                    selectedDetent: $selectedDetent
                )
            case .subject:
                SubjectFormView(
                    viewModel: reviewViewModel,
                    undoManager: isEditing ? undoManager : nil,
                    isReadOnly: !isEditing,
                    selectedDetent: $selectedDetent
                )
            case .none:
                EmptyView()
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.onChange(of: proxy.size.height, initial: true) { _, newHeight in
                    currentSheetHeight = newHeight
                }
            }
        }
        .presentationDetents([.height(76), .medium, .large], selection: $selectedDetent)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(76)))
        .interactiveDismissDisabled(true)
        .presentationDragIndicator(.visible)
        .presentationBackground {
            if selectedDetent == .large {
                DesignTokens.sheetBackground
            } else if #available(iOS 26, *) {
                Color.clear.glassEffect(.clear, in: .rect)
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
    }
}
