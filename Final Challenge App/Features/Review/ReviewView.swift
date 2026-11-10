    import SwiftUI

    /// Top-down lighting diagram after the scan, and editing it (Sketch R04, R09 · A10-10, A10-17).
    struct ReviewView: View {
        let isFromLoadingScreen: Bool // kalau true berarti dari page scan setup, kalau false berarti dari home
        @Bindable var viewModel: ReviewViewModel
        
        @Environment(\.undoManager) private var undoManager
        @Environment(\.dismiss) private var dismiss // Used to close the view
        
        @State private var editingNode: Equipment? = nil
        @State private var isAddingNode = false
        @State private var navigateToR07 = false
        @State private var showHint = true
        @State private var selectedNewCategory: EquipmentCategory = .light
        
        // State untuk memicu Alert saat keluar dari scan setup
        @State private var showDiscardAlert = false
        
        var body: some View {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    // Editable Canvas
                    LightingDiagramView(
                        viewModel: viewModel,
                        isReadOnly: false,
                        undoManager: undoManager,
                        onNodeTap: { node in editingNode = node }
                    )
                    .overlay(alignment: .bottomTrailing) {
                        Button {
                            isAddingNode = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(Color.gray, in: .circle)
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        }
                        .accessibilityLabel("New Setup")
                        .padding(16)
                    }
                    
                    // Mini Alert Overlay
                    if showHint {
                        HStack {
                            Text("Long press to move/rotate, or tap to edit details")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            Button(action: {
                                withAnimation { showHint = false }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color(uiColor: .systemBackground))
                                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    }
                }
                
                // Editable Carousel
                EquipmentCarousel(
                    viewModel: viewModel,
                    isReadOnly: false,
                    onNodeTap: { node in editingNode = node }
                )
            }
            .navigationBarBackButtonHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.canUndo || viewModel.canRedo {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") {
                            handleClose()
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isFromLoadingScreen ? "Review Setup" : "Edit Layout")
                                .font(.headline)
                                .fontWeight(.bold)
                            Text("\(viewModel.nodes.count) Lights")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    ToolbarItem {
                        HStack(spacing: 16) {
                            Button(action: {
                                undoManager?.undo()
                                viewModel.updateUndoState(undoManager: undoManager)
                            }) {
                                Image(systemName: "arrow.uturn.backward")
                            }
                            .disabled(!viewModel.canUndo)
                            
                            Button(action: {
                                undoManager?.redo()
                                viewModel.updateUndoState(undoManager: undoManager)
                            }) {
                                Image(systemName: "arrow.uturn.forward")
                            }
                            .disabled(!viewModel.canRedo)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark") {
                            undoManager?.removeAllActions()
                            viewModel.updateUndoState(undoManager: undoManager)
                            dismiss()
                        }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") {
                            handleClose()
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 2) {
                            Text(isFromLoadingScreen ? "Review Setup" : "Edit Layout")
                                .font(.headline)
                                .fontWeight(.bold)
                            Text("\(viewModel.nodes.count) Lights")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: isFromLoadingScreen ? "chevron.right" : "checkmark") {
                            undoManager?.removeAllActions()
                            viewModel.updateUndoState(undoManager: undoManager)
                            if isFromLoadingScreen {
                                navigateToR07 = true
                            } else {
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $navigateToR07) {
    //            R07_ProjectDetailsView(viewModel: viewModel, isPresentedModally: false)
            }
            .sheet(item: $editingNode) { node in
    //            R05_R06_EquipmentFormView(viewModel: viewModel, editingNodeId: node.id, undoManager: undoManager)
            }
            .sheet(isPresented: $isAddingNode) {
    //            R05_R06_EquipmentFormView(viewModel: viewModel, editingNodeId: nil, undoManager: undoManager)
            }
            // MARK: - Native Discard Alert
            .alert("Save This Setup?", isPresented: $showDiscardAlert) {
                Button("Save Setup") {
                    navigateToR07 = true
                }
                .keyboardShortcut(.defaultAction)
                
                Button("Discard Setup", role: .destructive) {
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("If you leave now, this scan and it's diagram will be lost.")
            }
        }
        
        // Helper function untuk menangani event Close
        private func handleClose() {
            if isFromLoadingScreen {
                showDiscardAlert = true
            } else {
                dismiss()
            }
        }
    }


    struct EquipmentCarousel: View {
        let viewModel: ReviewViewModel
        var isReadOnly: Bool = false
        var onNodeTap: ((Equipment) -> Void)? = nil
        
        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.nodes) { node in
                        VStack(alignment: .leading) {
                            Text("\(node.label) \(node.role)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                        .onTapGesture {
                            onNodeTap?(node)
                        }
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemBackground))
        }
    }

    #Preview {
        ReviewView(isFromLoadingScreen: false, viewModel: ReviewViewModel())
    }
