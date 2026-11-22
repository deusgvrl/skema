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
    @Binding var selectedNodeId: UUID?

    var onNodeTap: (Equipment) -> Void
    var onSubjectTap: () -> Void
    var onEmptyTap: (() -> Void)?

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
                    .padding(.top, 12)
                }
            }
        }
        .background(DesignTokens.pageBackground.ignoresSafeArea())
    }
}

/// A floating liquid-glass tip pill featuring leading icon and smooth dismissal.
private struct DiagramTipPill<TipType: Tip>: View {
    let tip: TipType
    @State private var isVisible = false

    var body: some View {
        ZStack {
            if isVisible {
                HStack(spacing: 10) {
                    // Leading Contextual Icon
                    Image(systemName: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.accentPrimary)

                    // Tip Title Text
                    tip.title
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Close Target
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            tip.invalidate(reason: .tipClosed)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(DesignTokens.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss tip")
                }
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            for await status in tip.statusUpdates {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isVisible = status == .available
                }
            }
        }
    }
}

struct ReviewViewModeTip: Tip {
    var title: Text {
        Text("Tap the pencil to edit your equipment")
    }
}

struct ReviewEditModeTip: Tip {
    var title: Text {
        Text("Tap equipment to move, rotate, or edit details")
    }
}

#Preview {
    ReviewDiagramContentView(
        viewModel: ReviewViewModel(),
        selectedNodeId: .constant(nil),
        onNodeTap: { _ in },
        onSubjectTap: {}
    )
}
