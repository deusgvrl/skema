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

    @State private var isDeleteAlert: Bool = false
    @State private var isControlsHidden: Bool = false
    @State private var isZoomed: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var scrollPositionID: Int?
    @State private var isDraggingDown: Bool = false

    private let feedbackGenerator = UISelectionFeedbackGenerator()

    // Dynamic background opacity based on drag distance
    private var backgroundOpacity: Double {
        if isControlsHidden { return 1.0 }
        let progress = max(0, dragOffset.height) / 300.0
        return max(0.0, 1.0 - progress)
    }

    // Slight scale reduction while dragging down (Native iOS Photos polish)
    private var dragScale: CGFloat {
        let progress = max(0, dragOffset.height) / 1000.0
        return max(0.85, 1.0 - progress)
    }

    var body: some View {
        ZStack {
            // Layer 1: Background Layer (Fades to transparent as user drags down)
            Color(isControlsHidden ? .black : .systemBackground)
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            // Layer 2: Main Image Viewer & Thumbnail Strip Content
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // Paging Main Image View (Drag-to-dismiss gesture attached directly here)
                TabView(selection: $selectedIndex) {
                    ForEach(0..<viewModel.referenceImages.count, id: \.self) { index in
                        if viewModel.referenceImages.indices.contains(index) {
                            ZoomableImageView(
                                image: viewModel.referenceImages[index],
                                isSelected: index == selectedIndex,
                                isZoomed: $isZoomed,
                                isControlsHidden: $isControlsHidden
                            )
                            .tag(index)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .simultaneousGesture(
                    isZoomed ? nil : dragToDismissGesture
                )

                Spacer(minLength: 0)

                // Bottom Centered Thumbnail Strip Overlay (Isolated from drag-to-dismiss)
                if !viewModel.referenceImages.isEmpty {
                    GeometryReader { geometry in
                        let selectedSize: CGFloat = 44
                        let unselectedWidth: CGFloat = 28
                        let height: CGFloat = 44
                        let centerPadding = max(0, (geometry.size.width - selectedSize) / 2)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
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
                                                    .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                                            )
                                            .opacity(isSelected ? 1.0 : 0.5)
                                            .contentShape(Rectangle())
                                            .id(index)
                                            .onTapGesture {
                                                feedbackGenerator.selectionChanged()
                                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                    selectedIndex = index
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
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                    selectedIndex = newID
                                }
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
                    .frame(height: 56)
                    .padding(.bottom, 16)
                    .opacity(isControlsHidden ? 0 : 1)
                    .allowsHitTesting(!isControlsHidden)
                }
            }
            .offset(y: max(0, dragOffset.height))
            .scaleEffect(dragScale)
        }
        .statusBarHidden(isControlsHidden)
        .toolbar(isControlsHidden ? .hidden : .visible, for: .navigationBar)
        .toolbar(isControlsHidden ? .hidden : .visible, for: .bottomBar)
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
        .alert("Delete This Photo", isPresented: $isDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteCurrentImage()
            }
        } message: {
            Text("It will be removed from this setup's references.")
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    let displayIndex = viewModel.referenceImages.isEmpty ? 0 : min(selectedIndex + 1, viewModel.referenceImages.count)
                    let currentRefImage = viewModel.sortedReferenceImages.indices.contains(selectedIndex)
                        ? viewModel.sortedReferenceImages[selectedIndex]
                        : nil

                    Text("Reference \(displayIndex)")
                        .font(.headline)
                        .fontWeight(.bold)

                    if let currentRefImage {
                        Text("\(displayIndex) of \(viewModel.referenceImages.count) · Added \(currentRefImage.formattedDateString)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(displayIndex) of \(viewModel.referenceImages.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            ToolbarSpacer(placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                Button("Delete", systemImage: "trash") {
                    isDeleteAlert = true
                }
                .disabled(viewModel.referenceImages.isEmpty)
            }
        }
    }

    // Drag-down gesture logic
    private var dragToDismissGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
        .onChanged { value in
            let horizontal = abs(value.translation.width)
            let vertical = value.translation.height

            if !isDraggingDown {
                // Evaluate direction ONLY once at the start of the drag
                if vertical > 8 && vertical > horizontal * 1.15 {
                    isDraggingDown = true
                    dragOffset = value.translation
                }
            } else {
                // Once locked in, update continuously every frame without re-checking slope
                dragOffset = value.translation
            }
        }
        .onEnded { value in
            let vertical = value.translation.height
            let predictedVelocity = value.predictedEndTranslation.height

            if isDraggingDown && (vertical > 120 || predictedVelocity > 350) {
                dismiss()
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    dragOffset = .zero
                }
            }
            isDraggingDown = false
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
}
