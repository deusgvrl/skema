import SwiftUI
import PhotosUI

/// One saved setup with Diagram and References tabs (Sketch R08 · A10-13).
struct SetupDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @State private var viewModel: SetupDetailViewModel

    // Photo Pickers State
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoPickerSelection: [PhotosPickerItem] = []

    // Selection & Preview State
    @State private var selectedImageIndices: Set<Int> = []
    @State private var selectedPreviewIndex: Int = 0
    @State private var showReferenceDetail: Bool = false
    @State private var showDeleteConfirmation: Bool = false

    // Diagram & Edit State
    @State private var isReadOnly: Bool = true
    @State private var editingNode: Equipment? = nil
    @State private var isAddingNode: Bool = false
    @State private var isShowSubjectSheet: Bool = false
    @State private var showDiscardAlert: Bool = false

    init(setup: Setup, storageController: StorageController? = nil) {
        self._viewModel = State(initialValue: SetupDetailViewModel(
            setup: setup,
            storageController: storageController
        ))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            // Segmented Tab Control (hidden in edit mode)
            if isReadOnly {
                Picker("Tabs", selection: $viewModel.selectedTab) {
                    Text("Diagram").tag(0)
                    Text("References").tag(1)
                }
                .pickerStyle(.segmented)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            if !isReadOnly || viewModel.selectedTab == 0 {
                // MARK: - Diagram Tab (Reusable ReviewDiagramContentView)
                ReviewDiagramContentView(
                    viewModel: viewModel.reviewViewModel,
                    undoManager: undoManager,
                    isReadOnly: isReadOnly,
                    onNodeTap: { node in
                        editingNode = node
                    },
                    onSubjectTap: {
                        isShowSubjectSheet = true
                    },
                    onAddNodeTap: {
                        isAddingNode = true
                    },
                    onEditTap: {
                        withAnimation {
                            isReadOnly = false
                        }
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
        .navigationBarBackButtonHidden(!isReadOnly)
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
            if !isReadOnly {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        if viewModel.reviewViewModel.canUndo {
                            showDiscardAlert = true
                        } else {
                            withAnimation {
                                isReadOnly = true
                            }
                        }
                    }
                }
            }
            
            ToolbarItem(placement: .principal) {
                VStack(alignment: !isReadOnly && (viewModel.reviewViewModel.canUndo || viewModel.reviewViewModel.canRedo) ? .leading : .center, spacing: 2) {
                    Text(viewModel.setupName)
                        .font(.headline)
                        .fontWeight(.bold)
                    Text(viewModel.formattedSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            ToolbarItemGroup(placement: .confirmationAction) {
                if !isReadOnly {
                    // Edit Mode Toolbar: Undo/Redo + Checkmark Save Button
                    if viewModel.reviewViewModel.canUndo || viewModel.reviewViewModel.canRedo {
                        Button {
                            undoManager?.undo()
                            viewModel.reviewViewModel.updateUndoState(undoManager: undoManager)
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .disabled(!viewModel.reviewViewModel.canUndo)

                        Button {
                            undoManager?.redo()
                            viewModel.reviewViewModel.updateUndoState(undoManager: undoManager)
                        } label: {
                            Image(systemName: "arrow.uturn.forward")
                        }
                        .disabled(!viewModel.reviewViewModel.canRedo)
                    }

                    Button("Save", systemImage: "checkmark") {
                        viewModel.reviewViewModel.finalizeAndSaveSetup()
                        undoManager?.removeAllActions()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.reviewViewModel.updateUndoState(undoManager: undoManager)
                            isReadOnly = true
                        }
                    }
                } else if viewModel.selectedTab == 0 {
                    // Read-only Diagram Tab Toolbar: 3 dots Menu
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
                    // References Tab Toolbar
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

            if isReadOnly && viewModel.selectedTab == 1 {
                ToolbarSpacer(placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    if viewModel.isSelectionMode {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label(
                                selectedImageIndices.isEmpty ? "Delete" : "Delete (\(selectedImageIndices.count))",
                                systemImage: "trash"
                            )
                        }
                        .disabled(selectedImageIndices.isEmpty)
                        .confirmationDialog(
                            selectedImageIndices.count == 1
                                ? "This photo will be deleted from this setup."
                                : "These \(selectedImageIndices.count) photos will be deleted from this setup.",
                            isPresented: $showDeleteConfirmation,
                            titleVisibility: .hidden
                        ) {
                            Button(
                                selectedImageIndices.count == 1 ? "Delete Photo" : "Delete \(selectedImageIndices.count) Photos",
                                role: .destructive
                            ) {
                                deleteSelectedImages()
                            }
                            
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            Text(
                                selectedImageIndices.count == 1
                                    ? "This photo will be deleted from your setup reference."
                                    : "These photos will be deleted from your setup references."
                            )
                        }
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
        .navigationDestination(isPresented: $showReferenceDetail) {
            FullScreenImageView(
                viewModel: viewModel,
                selectedIndex: selectedPreviewIndex
            )
        }
        .sheet(item: $editingNode) { node in
            EquipmentFormView(
                viewModel: viewModel.reviewViewModel,
                editingNodeId: node.id,
                undoManager: isReadOnly ? nil : undoManager,
                isReadOnly: isReadOnly
            )
        }
        .sheet(isPresented: $isAddingNode) {
            EquipmentFormView(
                viewModel: viewModel.reviewViewModel,
                editingNodeId: nil,
                undoManager: undoManager,
                isReadOnly: false
            )
        }
        .sheet(isPresented: $isShowSubjectSheet) {
            SubjectFormView(
                viewModel: viewModel.reviewViewModel,
                undoManager: isReadOnly ? nil : undoManager,
                isReadOnly: isReadOnly
            )
        }
        .sheet(isPresented: $viewModel.isEditingProjectDetails) {
            NavigationStack {
                ProjectDetailsView(setup: viewModel.setup)
            }
        }
        .alert("Discard Unsaved Changes?", isPresented: $showDiscardAlert) {
            Button("Discard Changes", role: .destructive) {
                while undoManager?.canUndo == true {
                    undoManager?.undo()
                }
                undoManager?.removeAllActions()
                viewModel.reviewViewModel.updateUndoState(undoManager: undoManager)
                withAnimation {
                    isReadOnly = true
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Any edits you made to this diagram will be reverted.")
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

struct EquipmentCarouselSheet: View {
    @Binding var sheetDetents: PresentationDetent
    
    var body: some View {
        
    }
}

#Preview {
    SetupDetailView(setup: Setup())
}
