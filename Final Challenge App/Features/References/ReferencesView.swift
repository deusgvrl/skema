//
//  ReferencesView.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 23/11/26.
//

import SwiftUI
import PhotosUI

struct ReferencesView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @Bindable var viewModel: SetupDetailViewModel
    @Bindable var referencesViewModel: ReferencesViewModel

    @Namespace private var zoomNamespace

    var body: some View {
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
        .photosPicker(
            isPresented: $referencesViewModel.showPhotoPicker,
            selection: $referencesViewModel.photoPickerSelection,
            matching: .images
        )
        .task(id: referencesViewModel.photoPickerSelection) {
            guard !referencesViewModel.photoPickerSelection.isEmpty else { return }
            await viewModel.addReferenceImages(from: referencesViewModel.photoPickerSelection)
            referencesViewModel.photoPickerSelection.removeAll()
        }
        .fullScreenCover(isPresented: $referencesViewModel.showCamera) {
            CameraPicker(images: $viewModel.referenceImages) { capturedImage in
                viewModel.addReferenceImage(capturedImage)
            }
            .ignoresSafeArea()
        }
        .navigationDestination(isPresented: $referencesViewModel.showReferenceDetail) {
            FullScreenImageView(
                viewModel: viewModel,
                selectedIndex: referencesViewModel.selectedPreviewIndex,
                namespace: zoomNamespace
            )
        }
        .alert("Delete This Photo?", isPresented: $referencesViewModel.isDeleteImageAlertPresented) {
            Button("Cancel", role: .cancel) {
                referencesViewModel.imageIndexToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let index = referencesViewModel.imageIndexToDelete {
                    viewModel.deleteReferenceImage(at: index)
                }
                referencesViewModel.imageIndexToDelete = nil
            }
        } message: {
            Text("It will be removed from this setup.")
        }
        .fullScreenCover(isPresented: $referencesViewModel.showCameraDenied, onDismiss: {
            if referencesViewModel.openLibraryAfterDenied {
                referencesViewModel.openLibraryAfterDenied = false
                referencesViewModel.showPhotoPicker = true
            }
        }, content: {
            cameraDenied()
        })
    }

    // MARK: - Subviews

    @ViewBuilder
    private func referenceImageCell(at index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: viewModel.referenceImages[index])
                .resizable()
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipped()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            referencesViewModel.selectedPreviewIndex = index
            referencesViewModel.showReferenceDetail = true
        }
        .contextMenu {
            Button {
                viewModel.setAsCoverImage(at: index)
            } label: {
                Label("Set as Cover Photo", systemImage: "photo.artframe")
            }

            Divider()

            Button(role: .destructive) {
                referencesViewModel.imageIndexToDelete = index
                referencesViewModel.isDeleteImageAlertPresented = true
            } label: {
                Label("Delete Photo", systemImage: "trash")
            }
        }
        .matchedTransitionSource(id: index, in: zoomNamespace)
    }

    private var referencesEmptyState: some View {
        ContentUnavailableView {
            Label("No References Yet", systemImage: "photo")
        } description: {
            Text("""
            Add photos from the shoot, like the final shot or the set, \
            so you can match this setup next time. Tap + to add one.
            """)
        }
    }

    @ViewBuilder
    private func cameraDenied() -> some View {
        NavigationStack {
            ScanMessageView(
                title: "Camera Access Is Off",
                systemImage: "video.slash",
                message: Text("""
                    Skema Photo needs the camera to take reference photos. \
                    Turn it on in Settings, or choose a photo from your library.
                    """)
            ) {
                ScanPrimaryButton(title: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }

                Button("Choose from Library") {
                    referencesViewModel.openLibraryAfterDenied = true
                    referencesViewModel.showCameraDenied = false
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.accentText)
            }
            .padding(.horizontal, 24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        referencesViewModel.showCameraDenied = false
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, referencesViewModel.cameraPermission.status == .authorized {
                referencesViewModel.showCameraDenied = false
            }
        }
    }
}
