//
//  FullScreenImageView.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 14/11/26.
//

import SwiftUI

struct FullScreenImageView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SetupDetailViewModel
    @State var selectedIndex: Int
    let namespace: Namespace.ID

    @State private var isDeleteAlert: Bool = false
    @State private var isControlsHidden: Bool = false
    @State private var scrollPositionID: Int?

    /// Top bar height (status bar + navigation bar), kept at its largest so hiding the controls
    /// doesn't make the photo jump.
    @State private var topBarHeight: CGFloat = 0

    private let feedbackGenerator = UISelectionFeedbackGenerator()

    // Thumbnail strip: 56pt tall, 80pt above the bottom edge of the screen.
    private static let stripHeight: CGFloat = 56
    private static let stripBottomPadding: CGFloat = 80
    private static let photoGap: CGFloat = 8

    /// Keeps the fitted photo between the top bar and the thumbnail strip (Sketch R13b).
    private var photoInsets: UIEdgeInsets {
        UIEdgeInsets(
            top: topBarHeight + Self.photoGap,
            left: 0,
            bottom: Self.stripBottomPadding + Self.stripHeight + Self.photoGap,
            right: 0
        )
    }

    var body: some View {
        GeometryReader { geometry in
            content
                .onAppear { topBarHeight = max(topBarHeight, geometry.safeAreaInsets.top) }
                .onChange(of: geometry.safeAreaInsets.top) { _, top in
                    topBarHeight = max(topBarHeight, top)
                }
        }
    }

    private var content: some View {
        ZStack {
            // Layer 1: Background
            (isControlsHidden ? Color.black : DesignTokens.pageBackground)
                .ignoresSafeArea()

            // Layer 2: Pager (pinch zoom, double tap, swipe between photos)
            PhotoPager(
                images: viewModel.referenceImages,
                selection: $selectedIndex,
                fitInsets: photoInsets,
                contentKey: viewModel.sortedReferenceImages.map(\.id)
            ) {
                withAnimation(.snappy) { isControlsHidden.toggle() }
            }
            .ignoresSafeArea()

            // Layer 3: Thumbnail strip
            VStack {
                Spacer()

                if !viewModel.referenceImages.isEmpty {
                    GeometryReader { geometry in
                        let selectedSize: CGFloat = 44
                        let unselectedWidth: CGFloat = 28
                        let height: CGFloat = 44
                        let centerPadding = max(0, (geometry.size.width - selectedSize) / 2)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 2) {
                                ForEach(0..<viewModel.referenceImages.count, id: \.self) { index in
                                    if viewModel.referenceImages.indices.contains(index) {
                                        let isSelected = index == selectedIndex

                                        Image(uiImage: viewModel.referenceImages[index])
                                            .resizable()
                                            .scaledToFill()
                                            .frame(
                                                width: isSelected ? selectedSize : unselectedWidth,
                                                height: height
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: isSelected ? 8 : 4))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: isSelected ? 8 : 4)
                                                    .stroke(
                                                        isSelected ? DesignTokens.textPrimary : Color.clear,
                                                        lineWidth: 2
                                                    )
                                            )
                                            .opacity(isSelected ? 1.0 : 0.5)
                                            .contentShape(Rectangle())
                                            .id(index)
                                            .onTapGesture {
                                                feedbackGenerator.selectionChanged()
                                                selectedIndex = index
                                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                    scrollPositionID = index
                                                }
                                            }
                                    }
                                }
                            }
                            .scrollTargetLayout()
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedIndex)
                            .padding(.vertical, 4)
                        }
                        .safeAreaPadding(.horizontal, centerPadding)
                        .scrollTargetBehavior(.viewAligned)
                        .scrollPosition(id: $scrollPositionID, anchor: .center)
                        .onChange(of: scrollPositionID) { _, newID in
                            if let newID, viewModel.referenceImages.indices.contains(newID), newID != selectedIndex {
                                feedbackGenerator.selectionChanged()
                                selectedIndex = newID
                            }
                        }
                        .onChange(of: selectedIndex) { _, newIndex in
                            if scrollPositionID != newIndex {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    scrollPositionID = newIndex
                                }
                            }
                        }
                    }
                    .frame(height: Self.stripHeight)
                    .padding(.bottom, Self.stripBottomPadding)
                    .opacity(isControlsHidden ? 0 : 1)
                    .allowsHitTesting(!isControlsHidden)
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(isControlsHidden)
        .toolbar(isControlsHidden ? .hidden : .visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        // Native swipe-down dismiss + hero animation back to the tapped thumbnail
        .navigationTransition(.zoom(sourceID: selectedIndex, in: namespace))
        .onAppear {
            scrollPositionID = selectedIndex
            feedbackGenerator.prepare()
        }
        .onChange(of: viewModel.referenceImages.count) { _, newCount in
            if newCount == 0 {
                dismiss()
            } else if selectedIndex >= newCount {
                selectedIndex = max(0, newCount - 1)
                scrollPositionID = selectedIndex
            }
        }
        // R13c
        .alert("Delete This Photo?", isPresented: $isDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteCurrentImage()
            }
        } message: {
            Text("It will be removed from this setup.")
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    let displayIndex = viewModel.referenceImages.isEmpty
                        ? 0
                        : min(selectedIndex + 1, viewModel.referenceImages.count)
                    let currentRefImage = viewModel.sortedReferenceImages.indices.contains(selectedIndex)
                        ? viewModel.sortedReferenceImages[selectedIndex]
                        : nil

                    Text("Reference \(displayIndex)")
                        .font(.headline)
                        .foregroundStyle(DesignTokens.textPrimary)

                    if let currentRefImage {
                        let count = viewModel.referenceImages.count
                        let dateText = currentRefImage.formattedDateString
                        Text("\(displayIndex) of \(count) · Added \(dateText)")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                    } else {
                        Text("\(displayIndex) of \(viewModel.referenceImages.count)")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        setAsCoverImage()
                    } label: {
                        Label("Set as Cover Photo", systemImage: "photo.artframe")
                    }

                    Divider()

                    Button(role: .destructive) {
                        isDeleteAlert = true
                    } label: {
                        Label("Delete Photo", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .disabled(viewModel.referenceImages.isEmpty)
            }
        }
    }

    private func deleteCurrentImage() {
        guard !viewModel.referenceImages.isEmpty,
              viewModel.referenceImages.indices.contains(selectedIndex) else { return }

        let targetIndex = selectedIndex
        let remainingCount = viewModel.referenceImages.count - 1

        if remainingCount == 0 {
            dismiss()
            viewModel.deleteReferenceImage(at: targetIndex)
        } else {
            if selectedIndex >= remainingCount {
                selectedIndex = remainingCount - 1
            }
            viewModel.deleteReferenceImage(at: targetIndex)
            scrollPositionID = selectedIndex
        }
    }

    private func setAsCoverImage() {
        viewModel.setAsCoverImage(at: selectedIndex)
        selectedIndex = 0
        scrollPositionID = 0
        feedbackGenerator.selectionChanged()
    }
}
