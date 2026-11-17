import SwiftUI
import PhotosUI

/// One saved setup with Diagram and References tabs (Sketch R08 · A10-13).
struct SetupDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SetupDetailViewModel
    @State private var exportViewModel: ExportViewModel

    // Photo Pickers State
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoPickerSelection: [PhotosPickerItem] = []

    // Selection & Preview State
    @State private var selectedPreviewIndex: Int = 0
    @State private var showReferenceDetail: Bool = false

    init(setup: Setup, storageController: StorageController? = nil) {
        self._exportViewModel = State(initialValue: ExportViewModel(setup: setup))
        self._viewModel = State(initialValue: SetupDetailViewModel(
            setup: setup,
            storageController: storageController
        ))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            // Segmented Tab Control
            Picker("Tabs", selection: $viewModel.selectedTab) {
                Text("Diagram").tag(0)
                Text("References").tag(1)
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom, 8)

            if viewModel.selectedTab == 0 {
                // MARK: - Diagram Tab
                ZStack(alignment: .bottomTrailing) {
                    LightingDiagramView(
                        viewModel: viewModel.reviewViewModel,
                        isReadOnly: true,
                        onNodeTap: { node in
                            viewModel.selectedEquipment = node
                        },
                        onSubjectTap: {
                            viewModel.isShowSubjectSheet = true
                        }
                    )

                    // Edit Diagram FAB (Sketch R08)
                    Button {
                        viewModel.isEditingDiagram = true
                    } label: {
                        AccentCircleLabel(title: "Edit Diagram", systemImage: "pencil")
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                }

                // Equipment Carousel
                EquipmentCarousel(
                    viewModel: viewModel.reviewViewModel,
                    isReadOnly: true,
                    onNodeTap: { node in
                        viewModel.selectedEquipment = node
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
        .toolbar {
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
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit Project Details", systemImage: "pencil") {
                        viewModel.isEditingProjectDetails = true
                    }
                    Button("Share", systemImage: "square.and.arrow.up") {
                        exportViewModel.share()
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        viewModel.isDeleteAlertPresented = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
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
        .sheet(item: $viewModel.selectedEquipment) { node in
            EquipmentFormView(
                viewModel: viewModel.reviewViewModel,
                editingNodeId: node.id,
                undoManager: nil,
                isReadOnly: true
            )
        }
        .fullScreenCover(isPresented: $viewModel.isEditingDiagram) {
            NavigationStack {
                ReviewView(
                    isFromLoadingScreen: false,
                    viewModel: viewModel.reviewViewModel,
                    onDismissToSetups: {
                        viewModel.isEditingDiagram = false
                    }
                )
            }
        }
        .sheet(isPresented: $viewModel.isEditingProjectDetails) {
            NavigationStack {
                ProjectDetailsView(setup: viewModel.setup, isPresentedModally: true)
            }
        }
        .sheet(isPresented: $viewModel.isShowSubjectSheet) {
            SubjectFormView(viewModel: viewModel.reviewViewModel, undoManager: nil, isReadOnly: true)
        }
        // R15: the system share sheet with the setup's PDF
        .sheet(item: $exportViewModel.sharedPDF) { shared in
            ExportView(fileURL: shared.url) {
                exportViewModel.sharedPDF = nil
            }
            .presentationDetents([.medium, .large])
            .ignoresSafeArea()
        }
        // R15f
        .alert("Couldn’t Create PDF", isPresented: $exportViewModel.showsFailure) {
            Button("Cancel", role: .cancel) { }
            Button("Try Again") {
                exportViewModel.share()
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
            Text("The diagram, equipment and references will move to Recently Deleted for 30 days.")
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
