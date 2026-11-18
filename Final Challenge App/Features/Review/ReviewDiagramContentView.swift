//
//  ReviewDiagramContentView.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 13/11/26.
//
//  Diagram, tip, floating button and equipment chips (Sketch R04 view mode, R04m edit mode).
//

import SwiftUI
import TipKit

struct ReviewDiagramContentView: View {
    @Bindable var viewModel: ReviewViewModel
    var undoManager: UndoManager?
    @Binding var selectedNodeId: UUID? // 👈 Pass binding through

    var onNodeTap: (Equipment) -> Void
    var onSubjectTap: () -> Void
    var onEmptyTap: (() -> Void)? = nil

    private let viewTip = ReviewViewModeTip()
    private let editTip = ReviewEditModeTip()

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                LightingDiagramView(
                    viewModel: viewModel,
                    isReadOnly: !viewModel.isEditingDiagram,
                    undoManager: undoManager,
                    selectedNodeId: $selectedNodeId, 
                    onNodeTap: onNodeTap,
                    onSubjectTap: onSubjectTap,
                    onEmptyTap: onEmptyTap
                )
                
                if !viewModel.nodes.isEmpty {
                    Group {
                        if viewModel.isEditingDiagram {
                            DiagramTipPill(tip: editTip)
                        } else {
                            DiagramTipPill(tip: viewTip)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
        }
        .background(DesignTokens.pageBackground.ignoresSafeArea())
    }
}

/// A one-line glass tip with a close button, backed by TipKit so closing it is remembered.
private struct DiagramTipPill<TipType: Tip>: View {
    let tip: TipType
    @State private var isVisible = false

    var body: some View {
        // A ZStack, not a Group: modifiers on an empty Group never run, so the task would not start.
        ZStack {
            if isVisible {
                HStack(spacing: 12) {
                    tip.title
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Close Tip", systemImage: "xmark") {
                        tip.invalidate(reason: .tipClosed)
                    }
                    .labelStyle(.iconOnly)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                }
                .padding(.leading, 16)
                .padding(.trailing, 4)
                .glassControl(cornerRadius: 24)
                .transition(.opacity)
            }
        }
        .task {
            for await status in tip.statusUpdates {
                withAnimation { isVisible = status == .available }
            }
        }
    }
}

struct ReviewViewModeTip: Tip {
    var title: Text {
        Text("Tap the pencil to move or edit your equipment")
    }
}

/// Sketch says "Drag to move…"; the app keeps its long-press-then-drag gesture, so the copy says so.
struct ReviewEditModeTip: Tip {
    var title: Text {
        Text("Long-press an item to move or rotate it, or tap it to edit")
    }
}

#Preview {
//    ReviewDiagramContentView(
//        viewModel: ReviewViewModel(),
//        selectedNodeId: UUID(), onNodeTap: { _ in },
//        onSubjectTap: {}
//    )
//    .task {
//        try? Tips.resetDatastore()
//        try? Tips.configure([.displayFrequency(.immediate)])
//    }
}
