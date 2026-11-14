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

    // Zoom state
    @State private var currentScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var isDeleteAlert: Bool = false

    @State private var scrollPositionID: Int?

    private let feedbackGenerator = UISelectionFeedbackGenerator()

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // Paging Main Image View with Zoom
            TabView(selection: $selectedIndex) {
                ForEach(0..<viewModel.referenceImages.count, id: \.self) { index in
                    if viewModel.referenceImages.indices.contains(index) {
                        Image(uiImage: viewModel.referenceImages[index])
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(selectedIndex == index ? currentScale : 1.0)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        currentScale = lastScale * value
                                    }
                                    .onEnded { _ in
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            if currentScale < 1.0 {
                                                currentScale = 1.0
                                            } else if currentScale > 4.0 {
                                                currentScale = 4.0
                                            }
                                            lastScale = currentScale
                                        }
                                    }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    if currentScale > 1.0 {
                                        currentScale = 1.0
                                        lastScale = 1.0
                                    } else {
                                        currentScale = 2.5
                                        lastScale = 2.5
                                    }
                                }
                            }
                            .tag(index)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            Spacer(minLength: 0)

            // Bottom Centered Thumbnail Strip (Native Photos Behavior)
            if !viewModel.referenceImages.isEmpty {
                GeometryReader { geometry in
                    let selectedSize: CGFloat = 44
                    let unselectedWidth: CGFloat = 30
                    let height: CGFloat = 44
                    let centerPadding = (geometry.size.width - selectedSize) / 2

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
                        .padding(.horizontal, centerPadding)
                        .padding(.vertical, 4)
                    }
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
                        currentScale = 1.0
                        lastScale = 1.0
                    }
                }
                .frame(height: 56)
                .padding(.bottom, 16)
            }
        }
        .background(Color(uiColor: .systemBackground))
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
            // Title & Subtitle Metadata
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
