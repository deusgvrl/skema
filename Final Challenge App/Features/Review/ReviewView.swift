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
    @State private var showUnsavedEditsAlert = false
    @State private var isShowingSubjectSheet = false
    @State private var initialSubjectHeight: String = ""

    
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
                ReviewDiagramContentView(
                    viewModel: viewModel,
                    undoManager: undoManager,
                    onNodeTap: { node in editingNode = node },
                    onSubjectTap: { isShowingSubjectSheet = true },
                    onAddNodeTap: { isAddingNode = true }
                )
            } else {
                ReviewLoadingView(
                    progress: progress,
                    isScanComplete: isScanComplete,
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isShowingDiagram = true
                        }
                    }
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
            Text("If you leave now, this scan and it's diagram will be lost.")
        }
        .alert("Discard Unsaved Changes?", isPresented: $showUnsavedEditsAlert) {
            Button("Discard Changes", role: .destructive) {
                while undoManager?.canUndo == true {
                    undoManager?.undo()
                }
                
                // 2. Clear memory and close
                undoManager?.removeAllActions()
                viewModel.updateUndoState(undoManager: undoManager)
                dismiss()
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
            EquipmentFormView(viewModel: viewModel, editingNodeId: node.id, undoManager: undoManager)
        }
        .sheet(isPresented: $isAddingNode) {
            EquipmentFormView(viewModel: viewModel, editingNodeId: nil, undoManager: undoManager)
        }
        .sheet(isPresented: $isShowingSubjectSheet) {
            SubjectFormView(viewModel: viewModel, undoManager: undoManager)
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
                VStack(alignment: viewModel.canUndo || viewModel.canRedo ? .leading : .center, spacing: 2) {
                    Text(isFromLoadingScreen ? "Review Setup" : viewModel.draftSetup.setupName)
                        .font(.headline)
                        .fontWeight(.bold)
                    Text("\(viewModel.nodes.count) Equipment Items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            ToolbarItemGroup(placement: .confirmationAction) {
                            
                // Undo / Redo Buttons
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
                
                // Done / Save Button (Two-Tap Logic)
                Button("Done", systemImage: isFromLoadingScreen ? "chevron.right" : "checkmark") {
                    
                    if viewModel.canUndo || viewModel.canRedo {
                        // 1ST TAP: User has unsaved edits. Save and clear the stack.
                        viewModel.finalizeAndSaveSetup()
                        undoManager?.removeAllActions()
                        
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.updateUndoState(undoManager: undoManager)
                        }
                    } else {
                        // 2ND TAP (or no edits made): Undo stack is clean. Navigate away.
                        if isFromLoadingScreen {
                            navigateToR07 = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
    
    private func handleClose() {
        let hasUnsavedChanges = viewModel.canUndo
        
        if isFromLoadingScreen {
            if hasUnsavedChanges {
                // They are in a new scan and haven't saved yet
                showDiscardAlert = true
            } else {
                viewModel.discardSetup()
                dismissAll()
            }
        } else {
            if hasUnsavedChanges {
                // They are editing an existing setup and made changes
                showUnsavedEditsAlert = true
            } else {
                // No changes made, safe to close instantly
                dismiss()
            }
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

#Preview {
    ReviewView(isFromLoadingScreen: false, viewModel: ReviewViewModel())
}
