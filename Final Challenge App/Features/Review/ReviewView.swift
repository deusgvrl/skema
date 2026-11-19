import SwiftUI

/// Top-down lighting diagram after scan, and editing it (Sketch R04, R04m, R09 · A10-10, A10-17).
/// Opens in view mode (Next, pencil); the pencil enters edit mode (undo/redo, ✓, +). Moving items
/// keeps the long-press-then-drag gesture and only works in edit mode.
struct ReviewView: View {
    let isFromLoadingScreen: Bool
    @Bindable var viewModel: ReviewViewModel
    var onDismissToSetups: (() -> Void)?

    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss

    // Unified sheet content: either an equipment node or the subject
    @State private var activeSheetContent: DiagramSheetContent?
    @State private var selectedNodeId: UUID? = nil
    @State private var isAddingNode = false
    @State private var navigateToR07 = false
    @State private var showsSaveSetupAlert = false
    @State private var showsDiscardChangesAlert = false
    @State private var selectedDetent: PresentationDetent = .height(76)

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
            selectedNodeId: $selectedNodeId,
            onNodeTap: { node in
                handleNodeTap(node)
            },
            onSubjectTap: {
                handleSubjectTap()
            },
            onEmptyTap: {
                handleEmptyTap()
            }
        )
        .ignoresSafeArea(edges: .bottom)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            toolbarContent
        }
        .onAppear {
            if !isFromLoadingScreen && !viewModel.isEditingDiagram {
                viewModel.beginEditing(undoManager: undoManager)
            }
        }
        .alert("Save This Setup?", isPresented: $showsSaveSetupAlert) {
            Button("Save Setup") { navigateToR07 = true }
            .keyboardShortcut(.defaultAction)
            Button("Discard", role: .destructive) {
                viewModel.discardSetup()
                dismissAll()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("If you leave now, this scan and its diagram will be lost.")
        }
        .alert("Discard Changes?", isPresented: $showsDiscardChangesAlert) {
            Button("Keep Editing", role: .cancel) { }
            Button("Discard", role: .destructive) {
                viewModel.discardEdits(undoManager: undoManager)
                if !isFromLoadingScreen { dismiss() }
            }
        } message: {
            Text("Your changes to this diagram won't be saved.")
        }
        .navigationDestination(isPresented: $navigateToR07) {
            ProjectDetailsView(
                setup: viewModel.draftSetup,
                isPresentedModally: false,
                onDismissToSetups: onDismissToSetups
            )
        }
        // Unified sheet for both equipment and subject
        .sheet(isPresented: unifiedSheetBinding, onDismiss: {
            activeSheetContent = nil
            selectedNodeId = nil
            selectedDetent = .height(76)
        }) {
            unifiedSheetContent
        }
        .sheet(isPresented: $isAddingNode) {
            EquipmentFormView(viewModel: viewModel, editingNodeId: nil, undoManager: undoManager, isReadOnly: false)
        }
    }

    // MARK: - Unified Sheet

    private var unifiedSheetBinding: Binding<Bool> {
        Binding(
            get: { activeSheetContent != nil },
            set: { isPresented in
                if !isPresented {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedNodeId = nil
                        activeSheetContent = nil
                        selectedDetent = .height(76)
                    }
                }
            }
        )
    }

    @ViewBuilder
    private var unifiedSheetContent: some View {
        Group {
            switch activeSheetContent {
            case .equipment(let nodeId):
                EquipmentFormView(
                    viewModel: viewModel,
                    editingNodeId: nodeId,
                    undoManager: viewModel.isEditingDiagram ? undoManager : nil,
                    isReadOnly: !viewModel.isEditingDiagram,
                    selectedDetent: $selectedDetent
                )
            case .subject:
                SubjectFormView(
                    viewModel: viewModel,
                    undoManager: viewModel.isEditingDiagram ? undoManager : nil,
                    isReadOnly: !viewModel.isEditingDiagram,
                    selectedDetent: $selectedDetent
                )
            case .none:
                EmptyView()
            }
        }
        .presentationDetents([.height(76), .medium, .large], selection: $selectedDetent)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(76)))
        .interactiveDismissDisabled(true)
        .presentationDragIndicator(.visible)
        .presentationBackground(DesignTokens.sheetBackground)
    }

    // MARK: - Tap Handlers

    private func handleNodeTap(_ node: Equipment) {
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedDetent = .height(76)
        }
        selectedNodeId = node.id
        activeSheetContent = .equipment(node.id)
    }

    private func handleSubjectTap() {
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedDetent = .height(76)
        }
        selectedNodeId = nil
        activeSheetContent = .subject
    }

    private func handleEmptyTap() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedNodeId = nil
            activeSheetContent = nil
            selectedDetent = .height(76)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarSpacer(placement: .bottomBar)

        // Hide floating button when sheet is present
        if activeSheetContent == nil {
            ToolbarItem(placement: .bottomBar) {
                floatingButton
            }
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
                    if !isFromLoadingScreen { dismiss() }
                }
                .buttonStyle(.glassProminent)
                .tint(DesignTokens.accentPrimary)
                .disabled(!viewModel.hasPendingEdits)
            }
        } else {
            ToolbarItem(placement: .confirmationAction) {
                Button("Next", systemImage: "chevron.right") { navigateToR07 = true }
                .buttonStyle(.glassProminent)
                .tint(DesignTokens.accentPrimary)
            }
        }
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

    // MARK: - Helpers

    private func closeReview() {
        if isFromLoadingScreen {
            showsSaveSetupAlert = true
        } else {
            dismiss()
        }
    }

    private func closeEditMode() {
        if viewModel.hasPendingEdits {
            showsDiscardChangesAlert = true
        } else {
            viewModel.discardEdits(undoManager: undoManager)
            if !isFromLoadingScreen { dismiss() }
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
