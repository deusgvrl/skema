//
//  ReviewToolbarContent.swift
//  Skema Photo
//
//  Created by Satriya Handha Wibowo on 23/11/26.
//

import SwiftUI

/// Toolbar for `ReviewView`: close, title, undo/redo, save/next and the floating add/edit button.
/// State owned by `ReviewView` is passed in as bindings; compound actions come in as closures
/// so the original logic stays in one place.
struct ReviewToolbarContent: ToolbarContent {
    let viewModel: ReviewViewModel
    let undoManager: UndoManager?
    let isFromScanScreen: Bool

    @Binding var activeSheetContent: DiagramSheetContent?
    @Binding var selectedNodeId: UUID?
    @Binding var isAddingNode: Bool
    @Binding var navigateToProjectDetails: Bool
    @Binding var showsSaveSetupAlert: Bool
    @Binding var showsDiscardChangesAlert: Bool

    let onClose: () -> Void
    let onDiscardSetup: () -> Void
    let onDismiss: () -> Void

    var body: some ToolbarContent {
        ToolbarSpacer(placement: .bottomBar)

        // Hide floating button when sheet is present
        if activeSheetContent == nil {
            ToolbarItem(placement: .bottomBar) {
                floatingButton
            }
        }

        ToolbarItem(placement: .cancellationAction) {
            closeButton
        }

        if !viewModel.isEditingDiagram {
            ToolbarItem(placement: .principal) {
                titleView
            }
        }

        if viewModel.isEditingDiagram {
            ToolbarItem(placement: .confirmationAction) {
                undoRedoButtons
            }

            ToolbarSpacer(.fixed, placement: .confirmationAction)

            ToolbarItem(placement: .confirmationAction) {
                saveChangesButton
            }
        } else {
            ToolbarItem(placement: .confirmationAction) {
                nextButton
            }
        }
    }

    // MARK: - Items

    private var closeButton: some View {
        Button("Close", systemImage: "xmark") {
            onClose()
        }
        // Popovers on the X (like Reminders); tapping outside one keeps the user here.
        .confirmationDialog(
            "Save this setup? If you leave now, this scan and its diagram will be lost.",
            isPresented: $showsSaveSetupAlert,
            titleVisibility: .visible
        ) {
            Button("Save Setup") { navigateToProjectDetails = true }
                .keyboardShortcut(.defaultAction)
            Button("Discard Scan", role: .destructive) {
                onDiscardSetup()
            }
        }
        .confirmationDialog(
            "Are you sure you want to discard your changes to this diagram?",
            isPresented: $showsDiscardChangesAlert,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                viewModel.discardEdits(undoManager: undoManager)
                if !isFromScanScreen { onDismiss() }
            }
        }
    }

    private var titleView: some View {
        Text(isFromScanScreen ? "Review Setup" : viewModel.draftSetup.setupName)
            .font(.headline)
            .foregroundStyle(DesignTokens.textPrimary)
    }

    private var undoRedoButtons: some View {
        HStack(spacing: 4) {
            Button("Undo", systemImage: "arrow.uturn.backward") {
                undoManager?.undo()
                viewModel.updateUndoState(undoManager: undoManager)
            }
            .disabled(!viewModel.canUndo)

            Button("Redo", systemImage: "arrow.uturn.forward") {
                undoManager?.redo()
                viewModel.updateUndoState(undoManager: undoManager)
            }
            .disabled(!viewModel.canRedo)
        }
    }

    private var saveChangesButton: some View {
        Button("Save Changes", systemImage: "checkmark") {
            selectedNodeId = nil
            activeSheetContent = nil
            viewModel.confirmEdits(undoManager: undoManager)
            if !isFromScanScreen { onDismiss() }
        }
        .buttonStyle(.glassProminent)
        .tint(DesignTokens.accentPrimary)
        .disabled(!viewModel.hasPendingEdits)
    }

    private var nextButton: some View {
        Button("Next", systemImage: "chevron.right") {
            selectedNodeId = nil
            activeSheetContent = nil
            navigateToProjectDetails = true
        }
        .buttonStyle(.glassProminent)
        .tint(DesignTokens.accentPrimary)
    }

    @ViewBuilder
    private var floatingButton: some View {
        if viewModel.isEditingDiagram {
            Button {
                isAddingNode = true
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.glassProminent)
            .tint(DesignTokens.accentPrimary)
        } 
    }
}
