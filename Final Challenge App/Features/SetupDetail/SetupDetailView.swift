import SwiftUI
import QuickLook

struct SetupDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    @State private var viewModel: SetupDetailViewModel
    @State private var referencesViewModel = ReferencesViewModel()

    private static let diagramImageScale: CGFloat = 3

    // Unified diagram sheet state
    @State private var activeSheetContent: DiagramSheetContent?
    @State private var selectedNodeId: UUID?
    @State private var isAddingNode = false
    @State private var showsDiscardChangesAlert = false

    @State private var selectedDetent: PresentationDetent = .height(76)
    @State private var currentSheetHeight: CGFloat = 76

    private var isEditing: Bool { viewModel.reviewViewModel.isEditingDiagram }

    private var quickActionsOpacity: Double {
        let fadeStartHeight: CGFloat = 76
        let fadeDistance: CGFloat = 100
        let progress = min(max((currentSheetHeight - fadeStartHeight) / fadeDistance, 0.0), 1.0)
        return 1.0 - progress
    }

    private var quickActionsScale: CGFloat {
        let progress = 1.0 - quickActionsOpacity
        return 1.0 - (progress * 0.1)
    }

    init(setup: Setup, storageController: StorageController? = nil) {
        self._viewModel = State(initialValue: SetupDetailViewModel(
            setup: setup,
            storageController: storageController
        ))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                tabPicker

                if isEditing || viewModel.selectedTab == 0 {
                    diagramContent
                } else {
                    ReferencesView(
                        viewModel: viewModel,
                        referencesViewModel: referencesViewModel
                    )
                }
            }

            if isEditing,
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
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEditing)
        .onChange(of: viewModel.selectedTab) { _, _ in resetSheetState() }
        .onChange(of: viewModel.reviewViewModel.nodes) { _, newNodes in
            if let selectedId = selectedNodeId, !newNodes.contains(where: { $0.id == selectedId }) {
                resetSheetState()
            }
        }
        .toolbar {
            SetupDetailToolbarContent(
                viewModel: viewModel,
                referencesViewModel: referencesViewModel,
                undoManager: undoManager,
                activeSheetContent: activeSheetContent,
                showsDiscardChangesAlert: $showsDiscardChangesAlert,
                isAddingNode: $isAddingNode,
                onResetSheetState: resetSheetState,
                onShare: shareTapped
            )
        }
        .sheet(isPresented: unifiedSheetBinding, onDismiss: resetSheetState) {
            DiagramSheetView(
                activeSheetContent: activeSheetContent,
                reviewViewModel: viewModel.reviewViewModel,
                isEditing: isEditing,
                undoManager: undoManager,
                selectedDetent: $selectedDetent,
                currentSheetHeight: $currentSheetHeight
            )
        }
        .sheet(isPresented: $isAddingNode) {
            EquipmentFormView(
                viewModel: viewModel.reviewViewModel,
                editingNodeId: nil,
                undoManager: undoManager,
                isReadOnly: false
            )
            .presentationDetents([.large])
            .presentationBackground(DesignTokens.sheetBackground)
        }
        .sheet(isPresented: $viewModel.isEditingProjectDetails) {
            NavigationStack {
                ProjectDetailsView(setup: viewModel.setup, isPresentedModally: true)
                    .environment(\.setupSavedAction, nil)
            }
        }
        .quickLookPreview($viewModel.pdfURL)
        .alert("Couldn’t Create PDF", isPresented: $viewModel.isPDFFailedAlertPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Try Again") { shareTapped() }
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("Your setup is safe. Try again.")
        }
        .alert("Delete This Setup?", isPresented: $viewModel.isDeleteAlertPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel.deleteSetup { dismiss() }
            }
        } message: {
            Text(viewModel.deleteMessage)
        }
    }
}

// MARK: - Subviews
private extension SetupDetailView {
    @ViewBuilder
    var tabPicker: some View {
        if !isEditing {
            Picker("View", selection: $viewModel.selectedTab) {
                Text("Diagram").tag(0)
                Text("References").tag(1)
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    var diagramContent: some View {
        ReviewDiagramContentView(
            viewModel: viewModel.reviewViewModel,
            undoManager: undoManager,
            selectedNodeId: $selectedNodeId,
            isSubjectSelected: {
                if case .subject = activeSheetContent { return true }
                return false
            }(),
            onNodeTap: { node in handleNodeTap(node) },
            onSubjectTap: { handleSubjectTap() },
            onEmptyTap: { handleEmptyTap() },
            onNodeDragStart: { node in handleNodeDragStart(node) }
        )
        .ignoresSafeArea(edges: .bottom)
    }

    var unifiedSheetBinding: Binding<Bool> {
        Binding(
            get: { activeSheetContent != nil },
            set: { isPresented in
                if !isPresented { resetSheetState() }
            }
        )
    }
}

// MARK: - Actions & Handlers
private extension SetupDetailView {
    func resetSheetState() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedNodeId = nil
            activeSheetContent = nil
            selectedDetent = .height(76)
        }
    }

    func handleNodeTap(_ node: Equipment) {
        if !isEditing {
            withAnimation {
                viewModel.reviewViewModel.beginEditing(undoManager: undoManager)
            }
        }

        selectedNodeId = node.id
        activeSheetContent = .equipment(node.id)
    }

    func handleSubjectTap() {
        if !isEditing {
            withAnimation {
                viewModel.reviewViewModel.beginEditing(undoManager: undoManager)
            }
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedDetent = .height(76)
        }
        selectedNodeId = nil
        activeSheetContent = .subject
    }

    func handleEmptyTap() {
        resetSheetState()
    }

    func handleNodeDragStart(_ node: Equipment) {
        if case .equipment(let id) = activeSheetContent, id == node.id { return }

        selectedNodeId = node.id
        activeSheetContent = .equipment(node.id)
    }

    func quickDeleteNode(id: UUID) {
        guard let index = viewModel.reviewViewModel.nodes.firstIndex(where: { $0.id == id }) else {
            return
        }
        let oldNodes = viewModel.reviewViewModel.nodes.map { $0.clone() }
        viewModel.reviewViewModel.nodes.remove(at: index)
        viewModel.reviewViewModel.applyStateChange(oldNodes: oldNodes, undoManager: undoManager)

        resetSheetState()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    func shareTapped() {
        selectedNodeId = nil
        activeSheetContent = nil

        // Drawn at the PDF box's own size: `PDFDiagramLayout` fits the items into it.
        let box = PDFLayout.diagramCanvasSize
        let diagram = PDFDiagramView(nodes: viewModel.reviewViewModel.nodes,
                                     subjectRotationAngle: viewModel.reviewViewModel.draftSetup.subjectRotationAngle)
            .frame(width: box.width, height: box.height)
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: diagram)
        renderer.scale = Self.diagramImageScale
        viewModel.shareTapped(diagram: renderer.uiImage)
    }
}

#Preview {
    SetupDetailView(setup: Setup())
}
