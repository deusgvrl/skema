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
                                    Image(uiImage: viewModel.referenceImages[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                                        .aspectRatio(1, contentMode: .fit)
                                        .clipped()
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
                    Button(viewModel.isSelectionMode ? "Cancel" : "Select") {
                        withAnimation { viewModel.isSelectionMode.toggle() }
                    }
                    .disabled(viewModel.referenceImages.isEmpty)
                }
            }

            if viewModel.selectedTab == 1 {
                ToolbarSpacer(placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    if !viewModel.isSelectionMode {
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
        // Photos Picker
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerSelection, matching: .images)
        .onChange(of: photoPickerSelection) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                await viewModel.addReferenceImages(from: newItems)
                photoPickerSelection.removeAll()
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(images: $viewModel.referenceImages) { capturedImage in
                viewModel.addReferenceImage(capturedImage)
            }
            .ignoresSafeArea()
        }
        // Equipment Detail Sheet (Read-Only)
        .sheet(item: $viewModel.selectedEquipment) { node in
            EquipmentFormView(
                viewModel: viewModel.reviewViewModel,
                editingNodeId: node.id,
                undoManager: nil,
                isReadOnly: true
            )
        }
        // Edit Diagram Canvas Modal
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
        // Edit Project Details Modal (R07)
        .sheet(isPresented: $viewModel.isEditingProjectDetails) {
            NavigationStack {
                ProjectDetailsView(setup: viewModel.setup)
            }
        }
        // Subject Height Sheet (Read-Only)
        .sheet(isPresented: $viewModel.isShowSubjectSheet) {
            SubjectFormView(viewModel: viewModel.reviewViewModel, undoManager: nil, isReadOnly: true)
        }
        // Delete Confirmation Alert
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
}

#Preview {
    SetupDetailView(setup: Setup())
}
