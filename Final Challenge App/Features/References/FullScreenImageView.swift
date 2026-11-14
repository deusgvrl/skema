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

            // Bottom Thumbnail Strip
            if !viewModel.referenceImages.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(0..<viewModel.referenceImages.count, id: \.self) { index in
                                if viewModel.referenceImages.indices.contains(index) {
                                    let isSelected = index == selectedIndex

                                    Image(uiImage: viewModel.referenceImages[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: isSelected ? 52 : 42, height: isSelected ? 52 : 42)
                                        .clipShape(RoundedRectangle(cornerRadius: isSelected ? 8 : 6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: isSelected ? 8 : 6)
                                                .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                                        )
                                        .opacity(isSelected ? 1.0 : 0.6)
                                        .id(index)
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                selectedIndex = index
                                            }
                                        }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                    }
                    .frame(maxWidth: .infinity)
                    .onChange(of: selectedIndex) { _, newIndex in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if viewModel.referenceImages.indices.contains(newIndex) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                            currentScale = 1.0
                            lastScale = 1.0
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationBarBackButtonHidden(true)
        .onChange(of: viewModel.referenceImages.count) { _, newCount in
            if newCount == 0 {
                dismiss()
            } else if selectedIndex >= newCount {
                selectedIndex = max(0, newCount - 1)
            }
        }
        .alert("Delete This Photo", isPresented: $isDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteCurrentImage()
            }
        } message: {
            Text("It will be removed from this setups's references.")
        }
        .toolbar {
            // Circular Back Button
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left") {
                    dismiss()
                }
            }

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
            // Circular Delete Button
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
        }
    }
}
