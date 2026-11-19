import SwiftUI
import PhotosUI
import QuickLook

/// One saved setup with Diagram and References tabs (Sketch R08 · A10-13).
/// The pencil edits the diagram in place (Sketch R09, A10-101): tabs hide, X / undo-redo / ✓ show.
struct SetupDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @State private var viewModel: SetupDetailViewModel
    
    /// 3x keeps the diagram sharp when the PDF is printed.
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
    
    private var isEditing: Bool { viewModel.reviewViewModel.isEditingDiagram }
    
    init(setup: Setup, storageController: StorageController? = nil) {
        self._viewModel = State(initialValue: SetupDetailViewModel(
            setup: setup,
            storageController: storageController
        ))
    }
    
    var body: some View {
        @Bindable var viewModel = viewModel
        
        VStack(spacing: 0) {
            tabPicker
            
            if isEditing || viewModel.selectedTab == 0 {
                diagramContent
            } else {
                referencesContent
            }
        }
        .background(DesignTokens.pageBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEditing)
        .onChange(of: viewModel.selectedTab) { _, _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedNodeId = nil
                activeSheetContent = nil
                selectedDetent = .height(76)
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
    } // 👈 Added missing closing brace here for referencesContent
    
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
        let diagram = LightingDiagramView(viewModel: viewModel.reviewViewModel, isReadOnly: true)
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
