// swiftlint:disable type_body_length
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
        let fadeDistance: CGFloat = 100 // Fades out fully over 100pt of vertical drag
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
            // Main Content Layer
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

            if isEditing, case .equipment(let nodeId) = activeSheetContent, quickActionsOpacity > 0.01 {
                nodeQuickActionsToolbar(for: nodeId)
                    .padding(.bottom, currentSheetHeight + 8) // Moves 1:1 with finger
                    .opacity(quickActionsOpacity)            // Fades out continuously
                    .scaleEffect(quickActionsScale)
                    .allowsHitTesting(quickActionsOpacity > 0.5)
                    .zIndex(1)
            }
        }
        .background(DesignTokens.pageBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEditing)
        .onChange(of: viewModel.selectedTab) { _, _ in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selectedNodeId = nil
                activeSheetContent = nil
                selectedDetent = .height(76)
            }
        }
        .onChange(of: viewModel.reviewViewModel.nodes) { _, newNodes in
            if let selectedId = selectedNodeId, !newNodes.contains(where: { $0.id == selectedId }) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    selectedNodeId = nil
                    activeSheetContent = nil
                    selectedDetent = .height(76)
                }
            }
        }
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: unifiedSheetBinding, onDismiss: {
            activeSheetContent = nil
            selectedNodeId = nil
            selectedDetent = .height(76)
        }, content: {
            unifiedSheetContent
        })
        .sheet(isPresented: $isAddingNode) {
            EquipmentFormView(
                viewModel: viewModel.reviewViewModel,
                editingNodeId: nil,
                undoManager: undoManager,
                isReadOnly: false
            )
        }
        .sheet(isPresented: $viewModel.isEditingProjectDetails) {
            NavigationStack {
                ProjectDetailsView(setup: viewModel.setup, isPresentedModally: true)
                    .environment(\.setupSavedAction, nil)
            }
        }
        .quickLookPreview($viewModel.pdfURL)
        .alert("Couldn't Create PDF", isPresented: $viewModel.isPDFFailedAlertPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Try Again") {
                shareTapped()
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text("Something went wrong while building this PDF. Your setup is safe, so you can try again.")
        }
        .alert("Delete This Setup?", isPresented: $viewModel.isDeleteAlertPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel.deleteSetup {
                    dismiss()
                }
            }
        } message: {
            Text(viewModel.deleteMessage)
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
        guard let original = viewModel.reviewViewModel.nodes.first(where: { $0.id == id }) else { return }
        let oldNodes = viewModel.reviewViewModel.nodes.map { $0.clone() }

        let duplicate = original.clone()
        duplicate.id = UUID()
        duplicate.name = "\(original.name) Copy"
        duplicate.position = CGPoint(x: original.position.x + 24, y: original.position.y + 24)

        viewModel.reviewViewModel.nodes.append(duplicate)
        viewModel.reviewViewModel.applyStateChange(oldNodes: oldNodes, undoManager: undoManager)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedNodeId = duplicate.id
            activeSheetContent = .equipment(duplicate.id)
            selectedDetent = .height(76)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func quickDeleteNode(id: UUID) {
        guard let index = viewModel.reviewViewModel.nodes.firstIndex(where: { $0.id == id }) else { return }
        let oldNodes = viewModel.reviewViewModel.nodes.map { $0.clone() }

        viewModel.reviewViewModel.nodes.remove(at: index)
        viewModel.reviewViewModel.applyStateChange(oldNodes: oldNodes, undoManager: undoManager)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedNodeId = nil
            activeSheetContent = nil
            selectedDetent = .height(76)
        }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    // MARK: - Sub-Expressions

    @ViewBuilder
    private var tabPicker: some View {
        if !isEditing {
            Picker("Tabs", selection: $viewModel.selectedTab) {
                Text("Diagram").tag(0)
                Text("References").tag(1)
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private var diagramContent: some View {
        ReviewDiagramContentView(
            viewModel: viewModel.reviewViewModel,
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
                    viewModel: viewModel.reviewViewModel,
                    editingNodeId: nodeId,
                    undoManager: isEditing ? undoManager : nil,
                    isReadOnly: !isEditing,
                    selectedDetent: $selectedDetent
                )
            case .subject:
                SubjectFormView(
                    viewModel: viewModel.reviewViewModel,
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

    // MARK: - Toolbar Content

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing {
            editToolbar
        }

        principalToolbar

        if !isEditing {
            moreMenuToolbar
        }

        bottomToolbar
    }

    @ToolbarContentBuilder
    private var editToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close", systemImage: "xmark") {
                if viewModel.reviewViewModel.hasPendingEdits {
                    showsDiscardChangesAlert = true
                } else {
                    selectedNodeId = nil
                    activeSheetContent = nil
                    withAnimation { viewModel.reviewViewModel.discardEdits(undoManager: undoManager) }
                }
            }
            .confirmationDialog(
                "Are you sure you want to discard your changes to this diagram?",
                isPresented: $showsDiscardChangesAlert,
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) {
                    withAnimation { viewModel.reviewViewModel.discardEdits(undoManager: undoManager) }
                }
            }
        }

        ToolbarItem(placement: .confirmationAction) {
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

        ToolbarSpacer(.fixed, placement: .confirmationAction)

        ToolbarItem(placement: .confirmationAction) {
            Button("Save Changes", systemImage: "checkmark") {
                selectedNodeId = nil
                activeSheetContent = nil
                withAnimation { viewModel.reviewViewModel.confirmEdits(undoManager: undoManager) }
            }
            .buttonStyle(.glassProminent)
            .tint(DesignTokens.accentPrimary)
            .disabled(!viewModel.reviewViewModel.hasPendingEdits)
        }
    }

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

    @ToolbarContentBuilder
    private var moreMenuToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Edit Project Details", systemImage: "pencil") {
                    selectedNodeId = nil
                    activeSheetContent = nil
                    viewModel.isEditingProjectDetails = true
                }
                Button("Share", systemImage: "square.and.arrow.up") {
                    shareTapped()
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

    @ToolbarContentBuilder
    private var bottomToolbar: some ToolbarContent {
        ToolbarSpacer(placement: .bottomBar)

        if activeSheetContent == nil && (isEditing || viewModel.selectedTab == 0) {
            ToolbarItem(placement: .bottomBar) {
                floatingButton
            }
        } else if !isEditing && viewModel.selectedTab == 1 {
            ToolbarItem(placement: .bottomBar) {
                Menu {
                    Button("Take Photo", systemImage: "camera") { referencesViewModel.takePhotoTapped() }
                    Button("Choose from Library", systemImage: "photo.on.rectangle") { referencesViewModel.showPhotoPicker = true }
                } label: {
                    Label("Add Image", systemImage: "plus")
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
        } else {
            Button {
                withAnimation {
                    viewModel.reviewViewModel.beginEditing(undoManager: undoManager)
                }
            } label: {
                Image(systemName: "pencil")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.glassProminent)
            .tint(DesignTokens.accentPrimary)
        }
    }

    private func shareTapped() {
        selectedNodeId = nil
        activeSheetContent = nil
        let base = PDFLayout.diagramCanvasSize
        let canvas = DiagramCanvas.size(fitting: viewModel.reviewViewModel.nodes.map(\.position), base: base)
        let diagram = LightingDiagramView(viewModel: viewModel.reviewViewModel, isReadOnly: true, isExportedToPdf: true)
            .frame(width: canvas.width, height: canvas.height)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: diagram)
        renderer.scale = max(1, Self.diagramImageScale * base.width / canvas.width)
        viewModel.shareTapped(diagram: renderer.uiImage)
    }
}

#Preview {
    SetupDetailView(setup: Setup())
}
