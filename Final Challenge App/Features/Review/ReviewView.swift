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
    @State private var selectedNodeId: UUID?
    @State private var isAddingNode = false
    @State private var navigateToR07 = false
    @State private var showsSaveSetupAlert = false
    @State private var showsDiscardChangesAlert = false
    @State private var selectedDetent: PresentationDetent = .height(76)

    // Live sheet height state for interactive drag tracking
    @State private var currentSheetHeight: CGFloat = 76

    // Dynamic Opacity: 1.0 at 76pt -> 0.0 at 176pt (fades out as user drags up)
    private var quickActionsOpacity: Double {
        let fadeStartHeight: CGFloat = 76
        let fadeDistance: CGFloat = 100 // Fades out fully over 100pt of vertical drag
        let progress = min(max((currentSheetHeight - fadeStartHeight) / fadeDistance, 0.0), 1.0)
        return 1.0 - progress
    }

    // Subtle scale effect while fading (1.0 -> 0.9)
    private var quickActionsScale: CGFloat {
        let progress = 1.0 - quickActionsOpacity
        return 1.0 - (progress * 0.1)
    }

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
        ZStack(alignment: .bottom) {
            // Main Content Layer
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

            // Floating Quick Actions Toolbar (Tracks touch gesture & fades out live)
            if viewModel.isEditingDiagram,
               case .equipment(let nodeId) = activeSheetContent,
               quickActionsOpacity > 0.01 {
                nodeQuickActionsToolbar(for: nodeId)
                    .padding(.bottom, currentSheetHeight + 8) // Moves 1:1 with finger
                    .opacity(quickActionsOpacity)            // Fades out continuously
                    .scaleEffect(quickActionsScale)
                    .allowsHitTesting(quickActionsOpacity > 0.5)
                    .zIndex(1)
            }
        }
        .background(DesignTokens.pageBackground.ignoresSafeArea())
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
        .onChange(of: viewModel.nodes) { _, newNodes in
            if let selectedId = selectedNodeId, !newNodes.contains(where: { $0.id == selectedId }) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    selectedNodeId = nil
                    activeSheetContent = nil
                    selectedDetent = .height(76)
                }
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
        }, content: {
            unifiedSheetContent
        })
        .sheet(isPresented: $isAddingNode) {
            EquipmentFormView(viewModel: viewModel, editingNodeId: nil, undoManager: undoManager, isReadOnly: false)
        }
    }

    // MARK: - Floating Node Toolbar Component & Actions

    @ViewBuilder
    private func nodeQuickActionsToolbar(for nodeId: UUID) -> some View {
        HStack(spacing: 16) {
            Button(role: .destructive) {
                quickDeleteNode(id: nodeId)
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    private func duplicateNode(id: UUID) {
        guard let original = viewModel.nodes.first(where: { $0.id == id }) else { return }
        let oldNodes = viewModel.nodes.map { $0.clone() }

        let duplicate = original.clone()
        duplicate.id = UUID()
        duplicate.name = "\(original.name) Copy"
        duplicate.position = CGPoint(x: original.position.x + 24, y: original.position.y + 24)

        viewModel.nodes.append(duplicate)
        viewModel.applyStateChange(oldNodes: oldNodes, undoManager: undoManager)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedNodeId = duplicate.id
            activeSheetContent = .equipment(duplicate.id)
            selectedDetent = .height(76)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func quickDeleteNode(id: UUID) {
        guard let index = viewModel.nodes.firstIndex(where: { $0.id == id }) else { return }
        let oldNodes = viewModel.nodes.map { $0.clone() }

        viewModel.nodes.remove(at: index)
        viewModel.applyStateChange(oldNodes: oldNodes, undoManager: undoManager)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedNodeId = nil
            activeSheetContent = nil
            selectedDetent = .height(76)
        }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    // MARK: - Unified Sheet

    private var unifiedSheetBinding: Binding<Bool> {
        Binding(
            get: { activeSheetContent != nil },
            set: { isPresented in
                if !isPresented {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
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
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.height, initial: true) { _, newHeight in
                        currentSheetHeight = newHeight
                    }
            }
        }
        .presentationDetents([.height(76), .medium, .large], selection: $selectedDetent)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(76)))
        .interactiveDismissDisabled(true)
        .presentationDragIndicator(.visible)
        // Liquid glass effect for 76pt & Medium detents, solid color for Large
        .presentationBackground {
            if selectedDetent == .large {
                DesignTokens.sheetBackground
            } else {
                if #available(iOS 26, *) {
                    Color.clear
                        .glassEffect(.clear, in: .rect)
                } else {
                    Rectangle().fill(.regularMaterial)
                }
            }
        }
    }

    // MARK: - Tap Handlers

    private func handleNodeTap(_ node: Equipment) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedDetent = .height(76)
        }
        selectedNodeId = node.id
        activeSheetContent = .equipment(node.id)
    }

    private func handleSubjectTap() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedDetent = .height(76)
        }
        selectedNodeId = nil
        activeSheetContent = .subject
    }

    private func handleEmptyTap() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
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
