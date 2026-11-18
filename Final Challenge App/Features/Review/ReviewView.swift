import SwiftUI

/// Top-down lighting diagram after scan, and editing it (Sketch R04, R04m, R09 · A10-10, A10-17).
/// Opens in view mode (Next, pencil); the pencil enters edit mode (undo/redo, ✓, +). Moving items
/// keeps the long-press-then-drag gesture and only works in edit mode.
struct ReviewView: View {
    /// True when opened right after a scan (a new draft), false when opened from a saved setup.
    /// The name is kept from when a processing screen came first; Finish Scan now opens the diagram directly.
    let isFromLoadingScreen: Bool
    @Bindable var viewModel: ReviewViewModel
    var onDismissToSetups: (() -> Void)?

    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss

    @State private var editingNode: Equipment?
    @State private var isAddingNode = false
    @State private var navigateToR07 = false
    @State private var showsSaveSetupAlert = false
    @State private var showsDiscardChangesAlert = false
    @State private var isShowingSubjectSheet = false

    init(
        isFromLoadingScreen: Bool,
        viewModel: ReviewViewModel,
        onDismissToSetups: (() -> Void)? = nil
    ) {
        self.isFromLoadingScreen = isFromLoadingScreen
        self.viewModel = viewModel
        self.onDismissToSetups = onDismissToSetups
    }

    var body: some View {
        ReviewDiagramContentView(
            viewModel: viewModel,
            undoManager: undoManager,
            onNodeTap: { node in editingNode = node },
            onSubjectTap: { isShowingSubjectSheet = true }
        )
        .ignoresSafeArea(edges: .bottom)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            toolbarContent
        }
        .onAppear {
            // From a saved setup the pencil was already tapped (Edit Diagram), so start in edit mode.
            if !isFromLoadingScreen && !viewModel.isEditingDiagram {
                viewModel.beginEditing(undoManager: undoManager)
            }
        }
        // R04x
        .alert("Save This Setup?", isPresented: $showsSaveSetupAlert) {
            Button("Save Setup") {
                navigateToR07 = true
            }
            .keyboardShortcut(.defaultAction)
            Button("Discard", role: .destructive) {
                viewModel.discardSetup()
                dismissAll()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("If you leave now, this scan and its diagram will be lost.")
        }
        // R04mx
        .alert("Discard Changes?", isPresented: $showsDiscardChangesAlert) {
            Button("Keep Editing", role: .cancel) { }
            Button("Discard", role: .destructive) {
                viewModel.discardEdits(undoManager: undoManager)
                if !isFromLoadingScreen {
                    dismiss()
                }
            }
        } message: {
            Text("Your changes to this diagram won’t be saved.")
        }
        .navigationDestination(isPresented: $navigateToR07) {
            ProjectDetailsView(
                setup: viewModel.draftSetup,
                isPresentedModally: false,
                onDismissToSetups: onDismissToSetups
            )
        }
        .sheet(item: $editingNode) { node in
            // View mode shows the details read-only; editing needs the pencil first (A10-101).
            EquipmentFormView(
                viewModel: viewModel,
                editingNodeId: node.id,
                undoManager: viewModel.isEditingDiagram ? undoManager : nil,
                isReadOnly: !viewModel.isEditingDiagram
            )
        }
        .sheet(isPresented: $isAddingNode) {
            EquipmentFormView(viewModel: viewModel, editingNodeId: nil, undoManager: undoManager, isReadOnly: false)
        }
        .sheet(isPresented: $isShowingSubjectSheet) {
            SubjectFormView(
                viewModel: viewModel,
                undoManager: viewModel.isEditingDiagram ? undoManager : nil,
                isReadOnly: !viewModel.isEditingDiagram
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        
        ToolbarSpacer(placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            floatingButton
        }
        
        ToolbarItem(placement: .cancellationAction) {
            Button("Close", systemImage: "xmark") {
                if viewModel.isEditingDiagram {
                    closeEditMode()
                } else {
                    closeReview()
                }
            }
        }

        ToolbarItem(placement: .principal) {
            VStack(spacing: 2) {
                Text(isFromLoadingScreen ? "Review Setup" : viewModel.draftSetup.setupName)
                    .font(.headline)
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(viewModel.layoutSubtitle)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }

        if viewModel.isEditingDiagram {
            // One item, so the bar draws undo and redo in a single glass capsule (Sketch R04m).
            ToolbarItem(placement: .confirmationAction) {
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

            ToolbarSpacer(.fixed, placement: .confirmationAction)

            ToolbarItem(placement: .confirmationAction) {
                Button("Save Changes", systemImage: "checkmark") {
                    viewModel.confirmEdits(undoManager: undoManager)
                    if !isFromLoadingScreen {
                        dismiss()
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(DesignTokens.accentPrimary)
                .disabled(!viewModel.hasPendingEdits)
            }
        } else {
            ToolbarItem(placement: .confirmationAction) {
                Button("Next", systemImage: "chevron.right") {
                    navigateToR07 = true
                }
                .buttonStyle(.glassProminent)
                .tint(DesignTokens.accentPrimary)
            }
        }
    }
    
    
    /// Pencil in view mode (red), + in edit mode (glass) — Sketch R04 / R04m.
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
            
        } else {
            Button {
                viewModel.beginEditing(undoManager: undoManager)
            } label: {
                Image(systemName: "pencil")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.glassProminent)
            .tint(DesignTokens.accentPrimary)
        }
    }

    /// X in view mode (R04 → R04x). A fresh scan is unsaved until Add Details, so always ask.
    private func closeReview() {
        if isFromLoadingScreen {
            showsSaveSetupAlert = true
        } else {
            dismiss()
        }
    }

    /// X in edit mode (R04m → R04mx when something changed, else back to view mode).
    private func closeEditMode() {
        if viewModel.hasPendingEdits {
            showsDiscardChangesAlert = true
        } else {
            viewModel.discardEdits(undoManager: undoManager)
            if !isFromLoadingScreen {
                dismiss()
            }
        }
    }

    private func dismissAll() {
        if let onDismissToSetups {
            onDismissToSetups()
        } else {
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        ReviewView(isFromLoadingScreen: true, viewModel: ReviewViewModel())
    }
}
