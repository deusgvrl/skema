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

    // Diagram view / edit state
    @State private var editingNode: Equipment?
    @State private var isAddingNode = false
    @State private var isShowingSubjectSheet = false
    @State private var showsDiscardChangesAlert = false

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
            // Segmented Tab Control (hidden while editing the diagram, Sketch R09)
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

            if isEditing || viewModel.selectedTab == 0 {
                // MARK: - Diagram Tab (pencil in view mode, + in edit mode, chips below)
                ReviewDiagramContentView(
                    viewModel: viewModel.reviewViewModel,
                    undoManager: undoManager,
                    onNodeTap: { node in editingNode = node },
                    onSubjectTap: { isShowingSubjectSheet = true },
                    onAddNodeTap: { isAddingNode = true },
                    onEditTap: {
                        withAnimation { viewModel.reviewViewModel.beginEditing(undoManager: undoManager) }
                    }
                )

            } else {
                // MARK: - References Tab (Sketch R11, R13)
                ZStack(alignment: .bottomTrailing) {
                    if viewModel.referenceImages.isEmpty {
                        referencesEmptyState
                    } else {
                        ScrollView {
                            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(viewModel.referenceImages.indices, id: \.self) { index in
                                    Image(uiImage: viewModel.referenceImages[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                                        .aspectRatio(1, contentMode: .fit)
                                        .clipped()
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedPreviewIndex = index
                                            showReferenceDetail = true
                                        }
                                        .accessibilityLabel("Reference \(index + 1)")
                                        .accessibilityAddTraits(.isButton)
                                }
                            }
                        }
                    }

                    // R12: + opens Take Photo / Choose from Library
                    Menu {
                        Button("Take Photo", systemImage: "camera") { showCamera = true }
                        Button("Choose from Library", systemImage: "photo.on.rectangle") { showPhotoPicker = true }
                    } label: {
                        AccentCircleLabel(title: "Add Reference", systemImage: "plus")
                    }
                    .padding(16)
                }
            }
        }
        .background(DesignTokens.pageBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEditing)
        .toolbar {
            if isEditing {
                editToolbar
            }

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

            // R14 / R13m
            if !isEditing {
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
        // Direct Navigation Destination via boolean flag
        .navigationDestination(isPresented: $showReferenceDetail) {
            FullScreenImageView(
                viewModel: viewModel,
                selectedIndex: selectedPreviewIndex
            )
        }
        // View mode shows details read-only; the pencil makes them editable (A10-101).
        .sheet(item: $editingNode) { node in
            EquipmentFormView(
                viewModel: viewModel.reviewViewModel,
                editingNodeId: node.id,
                undoManager: isEditing ? undoManager : nil,
                isReadOnly: !isEditing
            )
        }
        .sheet(isPresented: $isAddingNode) {
            EquipmentFormView(viewModel: viewModel.reviewViewModel, editingNodeId: nil, undoManager: undoManager, isReadOnly: false)
        }
        .sheet(isPresented: $isShowingSubjectSheet) {
            SubjectFormView(
                viewModel: viewModel.reviewViewModel,
                undoManager: isEditing ? undoManager : nil,
                isReadOnly: !isEditing
            )
        }
        // R09x
        .alert("Discard Changes?", isPresented: $showsDiscardChangesAlert) {
            Button("Keep Editing", role: .cancel) { }
            Button("Discard", role: .destructive) {
                withAnimation { viewModel.reviewViewModel.discardEdits(undoManager: undoManager) }
            }
        } message: {
            Text("Your changes to this diagram won’t be saved.")
        }
        .sheet(isPresented: $viewModel.isEditingProjectDetails) {
            NavigationStack {
                ProjectDetailsView(setup: viewModel.setup, isPresentedModally: true)
                    // The list is hidden behind this screen, so no "Setup saved" toast here.
                    .environment(\.setupSavedAction, nil)
            }
        }
        // A10-99: the PDF opens in Quick Look (R15p), whose share button shows the share sheet (R15).
        .quickLookPreview($viewModel.pdfURL)
        // R15f
        .alert("Couldn’t Create PDF", isPresented: $viewModel.isPDFFailedAlertPresented) {
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

    /// Draws the diagram into an image for the PDF, then lets the view model make the file (A10-99).
    private func shareTapped() {
        let base = PDFLayout.diagramCanvasSize
        let canvas = DiagramCanvas.size(fitting: viewModel.reviewViewModel.nodes.map(\.position), base: base)
        let diagram = LightingDiagramView(viewModel: viewModel.reviewViewModel, isReadOnly: true)
            .frame(width: canvas.width, height: canvas.height)
            // Paper is light, whatever the phone's appearance.
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: diagram)
        // A bigger canvas gets a lower scale, so the image keeps about the same pixel size.
        renderer.scale = max(1, Self.diagramImageScale * base.width / canvas.width)
        viewModel.shareTapped(diagram: renderer.uiImage)
    }

    /// Edit mode (Sketch R09): X, undo/redo in one capsule, and a red ✓ once something changed.
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

    /// R11: glass circle icon, title and Sketch copy.
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
