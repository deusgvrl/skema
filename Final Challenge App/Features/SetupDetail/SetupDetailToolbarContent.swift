//
//  SetupDetailToolbarContent.swift
//  Skema Photo
//
//  Created by Satriya Handha Wibowo on 23/11/26.
//

import SwiftUI

/// Toolbar for `SetupDetailView`: edit-mode controls, title, "more" menu and the bottom floating button.
/// State owned by `SetupDetailView` is passed in as bindings; actions that live on the view
/// (`resetSheetState`, `shareTapped`) come in as closures so the original logic stays in one place.
struct SetupDetailToolbarContent: ToolbarContent {
    let viewModel: SetupDetailViewModel
    let referencesViewModel: ReferencesViewModel
    let undoManager: UndoManager?
    let activeSheetContent: DiagramSheetContent?

    @Binding var showsDiscardChangesAlert: Bool
    @Binding var isAddingNode: Bool

    let onResetSheetState: () -> Void
    let onShare: () -> Void

    private var isEditing: Bool { viewModel.reviewViewModel.isEditingDiagram }

    var body: some ToolbarContent {
        if isEditing {
            editToolbar
        } else {
            principalToolbar
            moreMenuToolbar
        }
        bottomToolbar
    }

    // MARK: - Edit

    @ToolbarContentBuilder
    private var editToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close", systemImage: "xmark") {
                if viewModel.reviewViewModel.hasPendingEdits {
                    showsDiscardChangesAlert = true
                } else {
                    onResetSheetState()
                    withAnimation {
                        viewModel.reviewViewModel.discardEdits(undoManager: undoManager)
                    }
                }
            }
            .confirmationDialog(
                "Are you sure you want to discard your changes to this diagram?",
                isPresented: $showsDiscardChangesAlert,
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) {
                    withAnimation {
                        viewModel.reviewViewModel.discardEdits(undoManager: undoManager)
                    }
                }
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            undoRedoButtons
        }

        ToolbarSpacer(.fixed, placement: .confirmationAction)

        ToolbarItem(placement: .confirmationAction) {
            Button("Save Changes", systemImage: "checkmark") {
                onResetSheetState()
                withAnimation {
                    viewModel.reviewViewModel.confirmEdits(undoManager: undoManager)
                }
            }
            .buttonStyle(.glassProminent)
            .tint(DesignTokens.accentPrimary)
            .disabled(!viewModel.reviewViewModel.hasPendingEdits)
        }
    }

    private var undoRedoButtons: some View {
        HStack(spacing: 4) {
            Button("Undo", systemImage: "arrow.uturn.backward") {
                undoManager?.undo()
                viewModel.reviewViewModel.updateUndoState(undoManager: undoManager)
            }
            .disabled(!viewModel.reviewViewModel.canUndo)

            Button("Redo", systemImage: "arrow.uturn.forward") {
                undoManager?.redo()
                viewModel.reviewViewModel.updateUndoState(undoManager: undoManager)
            }
            .disabled(!viewModel.reviewViewModel.canRedo)
        }
    }

    // MARK: - Principal

    @ToolbarContentBuilder
    private var principalToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 2) {
                Text(viewModel.setupName)
                    .font(.headline)
                    .foregroundStyle(DesignTokens.textPrimary)
                if !viewModel.formattedSubtitle.isEmpty {
                    Text(viewModel.formattedSubtitle)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - More Menu

    @ToolbarContentBuilder
    private var moreMenuToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Edit Setup Details", systemImage: "pencil") {
                    onResetSheetState()
                    viewModel.isEditingProjectDetails = true
                }
                Button("Share PDF", systemImage: "square.and.arrow.up") {
                    onShare()
                }
                .disabled(viewModel.isPreparingPDF)
                Button("Delete", systemImage: "trash", role: .destructive) {
                    viewModel.isDeleteAlertPresented = true
                }
            } label: {
                if viewModel.isPreparingPDF {
                    ProgressView()
                } else {
                    Image(systemName: "ellipsis")
                }
            }
            .accessibilityLabel("More")
        }
    }

    // MARK: - Bottom Bar

    @ToolbarContentBuilder
    private var bottomToolbar: some ToolbarContent {
        ToolbarSpacer(placement: .bottomBar)

        if activeSheetContent == nil && (isEditing || viewModel.selectedTab == 0) {
            ToolbarItem(placement: .bottomBar) { floatingButton }
        } else if !isEditing && viewModel.selectedTab == 1 {
            ToolbarItem(placement: .bottomBar) {
                Menu {
                    Button("Take Photo", systemImage: "camera") {
                        referencesViewModel.takePhotoTapped()
                    }
                    Button("Choose from Library", systemImage: "photo.on.rectangle") {
                        referencesViewModel.showPhotoPicker = true
                    }
                } label: {
                    Label("Add Photo", systemImage: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private var floatingButton: some View {
        if isEditing {
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
