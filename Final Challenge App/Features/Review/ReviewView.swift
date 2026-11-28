import SwiftUI

/// Top-down lighting diagram after scan, and editing it (Sketch R04, R04m, R09 · A10-10, A10-17).
/// Opens in view mode (Next, pencil); the pencil enters edit mode (undo/redo, ✓, +). Moving items
/// keeps the long-press-then-drag gesture and only works in edit mode.
struct ReviewView: View {
    let isFromScanScreen: Bool
    @Bindable var viewModel: ReviewViewModel
    var onDismissToSetups: (() -> Void)?

    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss

    // Unified sheet content: either an equipment node or the subject
    @State private var activeSheetContent: DiagramSheetContent?
    @State private var selectedNodeId: UUID?
    @State private var isAddingNode = false
    @State private var navigateToProjectDetails = false
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
        isFromScanScreen: Bool,
        viewModel: ReviewViewModel,
        onDismissToSetups: (() -> Void)? = nil
    ) {
        self.isFromScanScreen = isFromScanScreen
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
                isSubjectSelected: {
                    if case .subject = activeSheetContent { return true }
                    return false
                }(),
                onNodeTap: { node in
                    handleNodeTap(node)
                },
                onSubjectTap: {
                    handleSubjectTap()
                },
                onEmptyTap: {
                    handleEmptyTap()
                },
                onNodeDragStart: { node in handleNodeDragStart(node) }
            )

            // Floating Quick Actions Toolbar (Tracks touch gesture & fades out live)
            if viewModel.isEditingDiagram,
               let content = activeSheetContent,
               quickActionsOpacity > 0.01 {

                let nodeId: UUID? = {
                    if case .equipment(let id) = content { return id }
                    return nil
                }()

                NodeQuickActionsToolbar(
                    nodeId: nodeId,
                    showsDelete: nodeId != nil,
                    onDelete: { id in
                        quickDeleteNode(id: id)
                    }
                )
                .padding(.bottom, currentSheetHeight + 8)
                .opacity(quickActionsOpacity)
                .scaleEffect(quickActionsScale)
                .allowsHitTesting(quickActionsOpacity > 0.5)
                .zIndex(1)
            }
        }
        .background(DesignTokens.pageBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ReviewToolbarContent(
                viewModel: viewModel,
                undoManager: undoManager,
                isFromScanScreen: isFromScanScreen,
                activeSheetContent: $activeSheetContent,
                selectedNodeId: $selectedNodeId,
                isAddingNode: $isAddingNode,
                navigateToProjectDetails: $navigateToProjectDetails,
                showsSaveSetupAlert: $showsSaveSetupAlert,
                showsDiscardChangesAlert: $showsDiscardChangesAlert,
                onClose: {
                    if viewModel.isEditingDiagram {
                        closeEditMode()
                    } else {
                        closeReview()
                    }
                },
                onDiscardSetup: {
                    viewModel.discardSetup()
                    dismissAll()
                },
                onDismiss: { dismiss() },
                onResetSheetState: { resetSheetState() }
            )
        }
        .onAppear {
            if (!isFromScanScreen || viewModel.nodes.isEmpty) && !viewModel.isEditingDiagram {
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
        .navigationDestination(isPresented: $navigateToProjectDetails) {
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
            DiagramSheetView(
                activeSheetContent: activeSheetContent,
                reviewViewModel: viewModel,
                isEditing: viewModel.isEditingDiagram,
                undoManager: undoManager,
                selectedDetent: $selectedDetent,
                currentSheetHeight: $currentSheetHeight
            )
        })
        .sheet(isPresented: $isAddingNode) {
            EquipmentFormView(viewModel: viewModel, editingNodeId: nil, undoManager: undoManager, isReadOnly: false)
                .presentationDetents([.large])
                .presentationBackground(DesignTokens.sheetBackground)
        }
    }

    // MARK: - Node Actions

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

    // MARK: - Unified Sheet Binding

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

    // MARK: - Tap Handlers

    func resetSheetState() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedNodeId = nil
            activeSheetContent = nil
            selectedDetent = .height(76)
        }
    }

    func handleNodeTap(_ node: Equipment) {
        if !viewModel.isEditingDiagram {
            withAnimation {
                viewModel.beginEditing(undoManager: undoManager)
            }
        }
        selectedNodeId = node.id
        activeSheetContent = .equipment(node.id)
    }

    func handleSubjectTap() {
        if !viewModel.isEditingDiagram {
            withAnimation {
                viewModel.beginEditing(undoManager: undoManager)
            }
        }

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

    func handleNodeDragStart(_ node: Equipment) {
        // Only switch if a different item is currently active
        if case .equipment(let id) = activeSheetContent, id == node.id { return }

        selectedNodeId = node.id
        activeSheetContent = .equipment(node.id)
    }

    // MARK: - Helpers

    private func closeReview() {
        if isFromScanScreen {
            showsSaveSetupAlert = true
        } else {
            dismiss()
        }
    }

    private func closeEditMode() {
        if viewModel.hasPendingEdits {
            showsDiscardChangesAlert = true
        } else {
            resetSheetState()
            withAnimation {
                viewModel.discardEdits(undoManager: undoManager)
            }
            if !isFromScanScreen { dismiss() }
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
        ReviewView(isFromScanScreen: true, viewModel: ReviewViewModel())
    }
}
