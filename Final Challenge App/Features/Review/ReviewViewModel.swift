import Observation
import SwiftUI

/// State and actions for ReviewView.
/// Reads and writes data only through StorageController, and reloads on appear and after every change.

@Observable
final class ReviewViewModel {
    var nodes: [Equipment] = []
    var draftSetup: Setup
    
    var canUndo = false
    var canRedo = false
    
    init(setup: Setup? = nil) {
        if let existingSetup = setup {
            // It receives the setup passed from LoadingPageView!
            self.draftSetup = existingSetup
            self.nodes = existingSetup.nodes
        } else {
            self.draftSetup = Setup(setupName: "New Setup")
            self.nodes = []
        }
    }
    
    func updateUndoState(undoManager: UndoManager?) {
        self.canUndo = undoManager?.canUndo ?? false
        self.canRedo = undoManager?.canRedo ?? false
    }

    func applyStateChange(oldNodes: [Equipment], undoManager: UndoManager?) {
        let currentNodes = self.nodes
        undoManager?.registerUndo(withTarget: self) { target in
            target.applyStateChange(oldNodes: currentNodes, undoManager: undoManager)
            target.nodes = oldNodes
            target.updateUndoState(undoManager: undoManager)
        }
        updateUndoState(undoManager: undoManager)
    }
    
    // Call this function when project details already filled, and call in inside the sheet checkmark button
    func finalizeAndSaveSetup() {
        draftSetup.nodes = nodes
        StorageController.shared.addSetup(draftSetup)
    }
}
