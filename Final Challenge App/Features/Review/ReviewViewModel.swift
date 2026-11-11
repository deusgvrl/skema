import Observation
import SwiftUI

/// State and actions for ReviewView.
/// Reads and writes data only through StorageController, and reloads on appear and after every change.

@Observable
final class ReviewViewModel: Identifiable {
    let id = UUID()
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
            let newSetup = Setup(setupName: "New Setup")
            StorageController.shared.addSetup(newSetup)
            self.draftSetup = newSetup
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
    
    func addEquipment(_ equipment: Equipment, undoManager: UndoManager?) {
        let oldNodes = self.nodes
        nodes.append(equipment)
        StorageController.shared.addEquipment(equipment, to: draftSetup)
        applyStateChange(oldNodes: oldNodes, undoManager: undoManager)
    }

    /// Persists changes made to an existing equipment item in SwiftData.
    func updateEquipment(undoManager: UndoManager?) {
        let oldNodes = self.nodes
        StorageController.shared.save()
        applyStateChange(oldNodes: oldNodes, undoManager: undoManager)
    }
    
    // Call this function when project details already filled, and call in inside the sheet checkmark button
    func finalizeAndSaveSetup() {
        draftSetup.nodes = nodes
        StorageController.shared.save()
    }
}
