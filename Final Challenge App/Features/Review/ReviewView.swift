import SwiftUI

/// Top-down lighting diagram after scan, and editing it (Sketch R04, R09 · A10-10, A10-17).
struct ReviewView: View {
    let isFromLoadingScreen: Bool // true if coming from scan flow, false if opened from setups list
    @Bindable var viewModel: ReviewViewModel
    var onDismissToSetups: (() -> Void)? = nil
    
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Loading State (from LoadingPageView)
    @State private var isShowingDiagram: Bool
    @State private var progress: Double = 0.0
    @State private var isScanComplete: Bool = false
    @State private var showCancelAlert: Bool = false
    
    // MARK: - Diagram State
    @State private var editingNode: Equipment? = nil
    @State private var isAddingNode = false
    @State private var navigateToR07 = false
    @State private var showHint = true
    @State private var selectedNewCategory: EquipmentCategory = .light
    @State private var showDiscardAlert = false
    
    init(
        isFromLoadingScreen: Bool,
        viewModel: ReviewViewModel,
        onDismissToSetups: (() -> Void)? = nil
    ) {
        self.isFromLoadingScreen = isFromLoadingScreen
        self.viewModel = viewModel
        self.onDismissToSetups = onDismissToSetups
        // If not from scan, immediately show the diagram
        self._isShowingDiagram = State(initialValue: !isFromLoadingScreen)
    }
    
    var body: some View {
        Group {
            if isShowingDiagram {
                diagramContent
            } else {
                loadingContent
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            toolbarContent
        }
        .onAppear {
            if isFromLoadingScreen && !isScanComplete {
                startLoadingSimulation()
            }
        }
        // Alert while loading
        .alert("Cancel This Scan?", isPresented: $showCancelAlert) {
            Button("Continue", role: .cancel) { }
            Button("Cancel Scan", role: .destructive) {
                dismissAll()
            }
        } message: {
            Text("Your scan is still processing and will be lost.")
        }
        // Alert while reviewing diagram
        .alert("Save This Setup?", isPresented: $showDiscardAlert) {
            Button("Save Setup") {
                navigateToR07 = true
            }
            .keyboardShortcut(.defaultAction)
            
            Button("Discard Setup", role: .destructive) {
                dismissAll()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("If you leave now, this scan and it's diagram will be lost.")
        }
        .navigationDestination(isPresented: $navigateToR07) {
            ProjectDetailsView(
                setup: viewModel.draftSetup,
                isPresentedModally: false,
                onSave: { updatedSetup in
                    viewModel.draftSetup = updatedSetup
                    viewModel.finalizeAndSaveSetup()
                },
                onDismissToSetups: onDismissToSetups
            )
        }
        .sheet(item: $editingNode) { node in
            EquipmentFormView(viewModel: viewModel, editingNodeId: node.id, undoManager: undoManager)
        }
        .sheet(isPresented: $isAddingNode) {
            EquipmentFormView(viewModel: viewModel, editingNodeId: nil, undoManager: undoManager)
        }
    }
    
    // MARK: - Subviews
    
    private var loadingContent: some View {
        VStack(spacing: 40) {
            Image("loading_illustration")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .accessibilityLabel("Scan preview illustration")
            
            VStack(spacing: 16) {
                Text("Building Your Diagram...")
                    .font(.title2.weight(.semibold))
                
                Text("We're mapping your lights, cameras and backdrop, and measuring how far each one is from the subject.\n\nKeep the app open while this finishes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
            
            if isScanComplete {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isShowingDiagram = true
                    }
                } label: {
                    Text("Continue to Layout")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                let secondsLeft = max(1, Int((1.0 - progress) * 20))
                
                VStack(spacing: 12) {
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .padding(.horizontal, 32)
                    
                    Text("Measuring distances... About \(secondsLeft) seconds left")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    
                    Text("4 lights · 1 bounce · 2 cameras · backdrop found")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 40)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }
    
    private var diagramContent: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
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
                    .padding(16)
                }
                
                if showHint && !viewModel.nodes.isEmpty {
                    HStack {
                        Text("Long press to move/rotate, or tap to edit details")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Button {
                            withAnimation { showHint = false }
                        } label: {
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
            
            EquipmentCarousel(
                viewModel: viewModel,
                isReadOnly: false,
                onNodeTap: { node in editingNode = node }
            )
        }
    }
    
    // MARK: - Toolbar Content
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !isShowingDiagram {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close", systemImage: "xmark") {
                    showCancelAlert = true
                }
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Review Setup")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text("Processing scan")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") {
                    handleClose()
                }
            }
            ToolbarItem(placement: .principal) {
                VStack(alignment: viewModel.canUndo || viewModel.canRedo ?  .leading : .center, spacing: 2) {
                    Text(isFromLoadingScreen ? "Review Setup" : "Edit Layout")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text("\(viewModel.nodes.count) Lights")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            if viewModel.canUndo || viewModel.canRedo {
                ToolbarItem {
                    HStack(spacing: 16) {
                        Button {
                            undoManager?.undo()
                            viewModel.updateUndoState(undoManager: undoManager)
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .disabled(!viewModel.canUndo)
                        
                        Button {
                            undoManager?.redo()
                            viewModel.updateUndoState(undoManager: undoManager)
                        } label: {
                            Image(systemName: "arrow.uturn.forward")
                        }
                        .disabled(!viewModel.canRedo)
                    }
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
    
    // MARK: - Actions
    
    private func handleClose() {
        if isFromLoadingScreen {
            showDiscardAlert = true
        } else {
            dismiss()
        }
    }
    
    private func dismissAll() {
        if let onDismissToSetups {
            onDismissToSetups()
        } else {
            dismiss()
        }
    }
    
    private func startLoadingSimulation() {
        guard !isScanComplete else { return }
        Task {
            for i in 1...100 {
                try? await Task.sleep(nanoseconds: 40_000_000)
                await MainActor.run {
                    progress = Double(i) / 100.0
                }
            }
            await MainActor.run {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    isScanComplete = true
                }
            }
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
                        Text("\(node.name)")
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
