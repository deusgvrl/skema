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
    @State private var isReadOnly: Bool = true
    @State private var editingNode: Equipment? = nil
    @State private var isAddingNode = false
    @State private var navigateToR07 = false
    @State private var showDiscardAlert = false
    @State private var showUnsavedEditsAlert = false
    @State private var isShowingSubjectSheet = false
    
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
        self._isReadOnly = State(initialValue: true)
    }
    
    var body: some View {
        Group {
            if isShowingDiagram {
                ReviewDiagramContentView(
                    viewModel: viewModel,
                    undoManager: undoManager,
                    isReadOnly: isReadOnly,
                    onNodeTap: { node in editingNode = node },
                    onSubjectTap: { isShowingSubjectSheet = true },
                    onAddNodeTap: { isAddingNode = true },
                    onEditTap: {
                        withAnimation {
                            isReadOnly = false
                        }
                    }
                )
            } else {
                ReviewLoadingView(
                    progress: progress,
                    isScanComplete: isScanComplete,
                    nodes: viewModel.nodes
                )
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
                viewModel.discardSetup()
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
                viewModel.discardSetup()
                dismissAll()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("If you leave now, this scan and its diagram will be lost.")
        }
        .alert("Discard Unsaved Changes?", isPresented: $showUnsavedEditsAlert) {
            Button("Discard Changes", role: .destructive) {
                while undoManager?.canUndo == true {
                    undoManager?.undo()
                }
                
                undoManager?.removeAllActions()
                viewModel.updateUndoState(undoManager: undoManager)
                withAnimation {
                    isReadOnly = true
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Any edits you made to this diagram will be reverted.")
        }
        .navigationDestination(isPresented: $navigateToR07) {
            ProjectDetailsView(
                setup: viewModel.draftSetup,
                isPresentedModally: false,
                onDismissToSetups: onDismissToSetups
            )
        }
        .sheet(item: $editingNode) { node in
            EquipmentFormView(
                viewModel: viewModel,
                editingNodeId: node.id,
                undoManager: isReadOnly ? nil : undoManager,
                isReadOnly: isReadOnly
            )
        }
        .sheet(isPresented: $isAddingNode) {
            EquipmentFormView(
                viewModel: viewModel,
                editingNodeId: nil,
                undoManager: undoManager,
                isReadOnly: false
            )
        }
        .sheet(isPresented: $isShowingSubjectSheet) {
            SubjectFormView(
                viewModel: viewModel,
                undoManager: isReadOnly ? nil : undoManager,
                isReadOnly: isReadOnly
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
                VStack(alignment: !isReadOnly && (viewModel.canUndo || viewModel.canRedo) ? .leading : .center, spacing: 2) {
                    Text(isFromLoadingScreen ? "Review Setup" : viewModel.draftSetup.setupName)
                        .font(.headline)
                        .fontWeight(.bold)
                    Text("\(viewModel.nodes.count) Equipment Items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            ToolbarItemGroup(placement: .confirmationAction) {
                if !isReadOnly {
                    // Undo / Redo Buttons in Edit Mode
                    if viewModel.canUndo || viewModel.canRedo {
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
                    
                    // Edit Mode Save Button: Checkmark to save
                    Button("Save", systemImage: "checkmark") {
                        viewModel.finalizeAndSaveSetup()
                        undoManager?.removeAllActions()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.updateUndoState(undoManager: undoManager)
                            isReadOnly = true
                        }
                    }
                } else {
                    // View Only: Chevron Right to proceed to ProjectDetails
                    Button("Next", systemImage: "chevron.right") {
                        navigateToR07 = true
                    }
                }
            }
        }
    }
    
    private func handleClose() {
        if !isReadOnly {
            if viewModel.canUndo {
                showUnsavedEditsAlert = true
            } else {
                withAnimation {
                    isReadOnly = true
                }
            }
            return
        }
        
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
                withAnimation(.easeInOut(duration: 0.4)) {
                    isScanComplete = true
                    isShowingDiagram = true
                }
            }
        }
    }
}

#Preview {
    ReviewView(isFromLoadingScreen: false, viewModel: ReviewViewModel())
}
