import SwiftUI
import PhotosUI

/// One saved setup with Diagram and References tabs (Sketch R08 · A10-13).
struct SetupDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SetupDetailViewModel

    // Photo Pickers State
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoPickerSelection: [PhotosPickerItem] = []

    // Selection & Preview State
    @State private var selectedImageIndices: Set<Int> = []
    @State private var selectedPreviewIndex: Int = 0
    @State private var showReferenceDetail: Bool = false

    init(setup: Setup, storageController: StorageController? = nil) {
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

                    // Edit Diagram FAB
                    Button {
                        viewModel.isEditingDiagram = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Color.accentColor, in: .circle)
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    }
                    .accessibilityLabel("Edit Diagram")
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
                // MARK: - References Tab
                ZStack {
                    if viewModel.referenceImages.isEmpty {
                        ContentUnavailableView {
                            Label {
                                Text("No References Yet")
                                    .font(.title2.bold())
                            } icon: {
                                Image(systemName: "photo.on.rectangle")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, height: 80)
                                    .background(Color(.tertiarySystemFill), in: .circle)
                            }
                        } description: {
                            Text("Add photos from the shoot (final shot, set photos, product placement) to recreate this lighting setup anytime.")
                                .font(.subheadline)
                        }
                    } else {
                        ScrollView {
                            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(0..<viewModel.referenceImages.count, id: \.self) { index in
                                    if viewModel.referenceImages.indices.contains(index) {
                                        let isSelected = selectedImageIndices.contains(index)
                                        
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: viewModel.referenceImages[index])
                                                .resizable()
                                                .scaledToFill()
                                                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                                                .aspectRatio(1, contentMode: .fit)
                                                .clipped()
                                                .opacity(viewModel.isSelectionMode && isSelected ? 0.75 : 1.0)

                                            // Selection Checkmark Badge
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
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.selectedTab) { _, _ in
            viewModel.isSelectionMode = false
            selectedImageIndices.removeAll()
        }
        .onChange(of: viewModel.isSelectionMode) { _, isSelecting in
            if !isSelecting {
                selectedImageIndices.removeAll()
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(viewModel.setupName)
                        .font(.headline)
                        .fontWeight(.bold)

                    Text(viewModel.formattedSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                if viewModel.selectedTab == 0 {
                    Menu {
                        Button("Edit Project Details", systemImage: "pencil") {
                            viewModel.isEditingProjectDetails = true
                        }
                        Button("Share", systemImage: "square.and.arrow.up") { }
                        Divider()
                        Button("Delete Setup", systemImage: "trash", role: .destructive) {
                            viewModel.isDeleteAlertPresented = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                } else {
                    if viewModel.isSelectionMode {
                        Button("Cancel", systemImage: "xmark") {
                            withAnimation {
                                viewModel.isSelectionMode = false
                            }
                        }
                    } else {
                        Button("Select") {
                            withAnimation {
                                viewModel.isSelectionMode = true
                            }
                        }
                        .disabled(viewModel.referenceImages.isEmpty)
                    }
                }
            }

            if viewModel.selectedTab == 1 {
                ToolbarSpacer(placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    if viewModel.isSelectionMode {
                        Button(role: .destructive) {
                            deleteSelectedImages()
                        } label: {
                            Label(
                                selectedImageIndices.isEmpty ? "Delete" : "Delete (\(selectedImageIndices.count))",
                                systemImage: "trash"
                            )
                        }
                        .disabled(selectedImageIndices.isEmpty)
                    } else {
                        Menu {
                            Button {
                                showCamera = true
                            } label: {
                                Label("Take Photo", systemImage: "camera")
                            }

                            Button {
                                showPhotoPicker = true
                            } label: {
                                Label("Choose from Library", systemImage: "photo.on.rectangle")
                            }
                        } label: {
                            Label("Add Reference", systemImage: "plus")
                        }
                    }
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
                ProjectDetailsView(setup: viewModel.setup)
            }
        }
        .sheet(isPresented: $viewModel.isShowSubjectSheet) {
            SubjectFormView(viewModel: viewModel.reviewViewModel, undoManager: nil, isReadOnly: true)
        }
        .alert("Delete Setup", isPresented: $viewModel.isDeleteAlertPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel.deleteSetup {
                    dismiss()
                }
            }
        } message: {
            Text("Are you sure you want to delete this setup? This action cannot be undone.")
        }
    }

    private func deleteSelectedImages() {
        viewModel.deleteReferenceImages(at: selectedImageIndices)
        selectedImageIndices.removeAll()
        viewModel.isSelectionMode = false
    }
}

#Preview {
    SetupDetailView(setup: Setup())
}
