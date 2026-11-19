import SwiftUI
import PhotosUI
import QuickLook

struct SetupDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @State private var viewModel: SetupDetailViewModel
    
    private static let diagramImageScale: CGFloat = 3
    
    // Photo Pickers State
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoPickerSelection: [PhotosPickerItem] = []
    
    // Selection & Preview State
    @State private var selectedPreviewIndex: Int = 0
    @State private var showReferenceDetail: Bool = false
    @State private var selectedImageIndices: Set<Int> = []
    
    // Unified diagram sheet state
    @State private var activeSheetContent: DiagramSheetContent?
    @State private var selectedNodeId: UUID? = nil
    @State private var isAddingNode = false
    @State private var showsDiscardChangesAlert = false
    
    @State private var selectedDetent: PresentationDetent = .height(76)
    
    // 👈 Live sheet height state for interactive drag tracking
    @State private var currentSheetHeight: CGFloat = 76
    
    private var isEditing: Bool { viewModel.reviewViewModel.isEditingDiagram }
    
    // 👈 Dynamic Opacity: 1.0 at 76pt -> 0.0 at 176pt (fades out as user drags up)
    private var quickActionsOpacity: Double {
        let fadeStartHeight: CGFloat = 76
        let fadeDistance: CGFloat = 100 // Fades out fully over 100pt of vertical drag
        let progress = min(max((currentSheetHeight - fadeStartHeight) / fadeDistance, 0.0), 1.0)
        return 1.0 - progress
    }
    
    // 👈 Subtle scale effect while fading (1.0 -> 0.9)
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
                    referencesContent
                }
            }
            
            // 👈 Interactive Floating Toolbar (Tracks touch gesture & fades out live)
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
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerSelection, matching: .images)
        .task(id: photoPickerSelection) {
            guard !photoPickerSelection.isEmpty else { return }
            await viewModel.addReferenceImages(from: photoPickerSelection)
            photoPickerSelection.removeAll()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(images: $viewModel.referenceImages) { capturedImage in
                viewModel.addReferenceImage(capturedImage)
            }
            .ignoresSafeArea()
        }
        .navigationDestination(isPresented: $showReferenceDetail) {
            FullScreenImageView(
                viewModel: viewModel,
                selectedIndex: selectedPreviewIndex
            )
        }
        .sheet(isPresented: unifiedSheetBinding, onDismiss: {
            activeSheetContent = nil
            selectedNodeId = nil
            selectedDetent = .height(76)
        }) {
            unifiedSheetContent
        }
        .sheet(isPresented: $isAddingNode) {
            EquipmentFormView(
                viewModel: viewModel.reviewViewModel,
                editingNodeId: nil,
                undoManager: undoManager,
                isReadOnly: false
            )
        }
        .alert("Discard Changes?", isPresented: $showsDiscardChangesAlert) {
            Button("Keep Editing", role: .cancel) { }
            Button("Discard", role: .destructive) {
                withAnimation { viewModel.reviewViewModel.discardEdits(undoManager: undoManager) }
            }
        } message: {
            Text("Your changes to this diagram won't be saved.")
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
//            Button {
//                duplicateNode(id: nodeId)
//            } label: {
//                Image(systemName: "plus.square.on.square")
//                    .font(.subheadline.weight(.medium))
//                    .foregroundStyle(DesignTokens.textPrimary)
//            }
//            
//            Divider()
//                .frame(height: 16)
            
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
    
    @ViewBuilder
    private var referencesContent: some View {
        ZStack {
            if viewModel.referenceImages.isEmpty {
                referencesEmptyState
            } else {
                ScrollView {
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(0..<viewModel.referenceImages.count, id: \.self) { index in
                            if viewModel.referenceImages.indices.contains(index) {
                                referenceImageCell(at: index)
                                    .accessibilityLabel("Reference \(index + 1)")
                                    .accessibilityAddTraits(.isButton)
                            }
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func referenceImageCell(at index: Int) -> some View {
        let isSelected = selectedImageIndices.contains(index)
        
        ZStack(alignment: .topTrailing) {
            Image(uiImage: viewModel.referenceImages[index])
                .resizable()
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipped()
                .opacity(viewModel.isSelectionMode && isSelected ? 0.75 : 1.0)
            
            if viewModel.isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .white)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .padding(6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if viewModel.isSelectionMode {
                if isSelected {
                    selectedImageIndices.remove(index)
                } else {
                    selectedImageIndices.insert(index)
                }
            } else {
                selectedPreviewIndex = index
                showReferenceDetail = true
            }
        }
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
        // 👈 Tracks live sheet height as the user drags the sheet up or down
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
        .presentationBackground(DesignTokens.sheetBackground)
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
                    Button("Take Photo", systemImage: "camera") { showCamera = true }
                    Button("Choose from Library", systemImage: "photo.on.rectangle") { showPhotoPicker = true }
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
        let base = PDFLayout.diagramCanvasSize
        let canvas = DiagramCanvas.size(fitting: viewModel.reviewViewModel.nodes.map(\.position), base: base)
        let diagram = LightingDiagramView(viewModel: viewModel.reviewViewModel, isReadOnly: true, isExportedToPdf: true)
            .frame(width: canvas.width, height: canvas.height)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: diagram)
        renderer.scale = max(1, Self.diagramImageScale * base.width / canvas.width)
        viewModel.shareTapped(diagram: renderer.uiImage)
    }
    
    private var referencesEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 30))
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(width: 80, height: 80)
                .glassEffect(.regular.tint(DesignTokens.glassControlFill), in: .circle)
                .accessibilityHidden(true)
            Text("No References Yet")
                .font(.title2.bold())
                .foregroundStyle(DesignTokens.textPrimary)
            Text("""
            Add any photos from the shoot, like the final shot, the product, or the set, \
            so you can match this setup next time. Tap + to add a reference.
            """)
            .font(.subheadline)
            .foregroundStyle(DesignTokens.textSecondary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SetupDetailView(setup: Setup())
}
