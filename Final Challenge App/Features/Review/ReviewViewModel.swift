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
    
    @ObservationIgnored private let storageController: StorageController
    
    init(setup: Setup? = nil, storageController: StorageController? = nil) {
        let storage = storageController ?? StorageController.shared
        self.storageController = storageController ?? StorageController.shared

        if let existingSetup = setup {
            // It receives the setup passed from LoadingPageView!
            self.draftSetup = existingSetup
            self.nodes = existingSetup.nodes
        } else {
            let newSetup = Setup(setupName: "New Setup")
            storage.addSetup(newSetup)
            self.draftSetup = newSetup
            self.nodes = []
        }
    }
    
    func updateUndoState(undoManager: UndoManager?) {
        self.canUndo = undoManager?.canUndo ?? false
        self.canRedo = undoManager?.canRedo ?? false
    }
    
    func applyStateChange(oldNodes: [Equipment], undoManager: UndoManager?) {
        // Snapshot the current state BEFORE undoing
        let currentNodes = self.nodes.map { $0.clone() }
        
        undoManager?.registerUndo(withTarget: self) { target in
            let oldIds = Set(oldNodes.map { $0.id })
            let currentIds = Set(target.nodes.map { $0.id })
            
            // 1. DELETE items that were added after this snapshot
            let idsToDelete = currentIds.subtracting(oldIds)
            for id in idsToDelete {
                if let index = target.nodes.firstIndex(where: { $0.id == id }) {
                    let nodeToDelete = target.nodes[index]
                    target.nodes.remove(at: index)
                    
                    // NOTE: Call your specific SwiftData/Storage delete method here if you have one
                    target.storageController.deleteEquipment(nodeToDelete)
                }
            }
            
            // 2. ADD items that were deleted after this snapshot
            let idsToAdd = oldIds.subtracting(currentIds)
            for id in idsToAdd {
                if let nodeToAdd = oldNodes.first(where: { $0.id == id })?.clone() {
                    target.nodes.append(nodeToAdd)
                    target.storageController.addEquipment(nodeToAdd, to: target.draftSetup)
                }
            }
            
            // 3. RESTORE properties for items that survived
            for oldNode in oldNodes {
                if let existingNode = target.nodes.first(where: { $0.id == oldNode.id }) {
                    existingNode.restoreValues(from: oldNode)
                }
            }
            
            target.storageController.save()
            target.applyStateChange(oldNodes: currentNodes, undoManager: undoManager)
            target.updateUndoState(undoManager: undoManager)
        }
        
        updateUndoState(undoManager: undoManager)
    }
    
    func addEquipment(_ equipment: Equipment, undoManager: UndoManager?) {
        let oldNodes = self.nodes.map { $0.clone() }
        nodes.append(equipment)
        storageController.addEquipment(equipment, to: draftSetup)
        applyStateChange(oldNodes: oldNodes, undoManager: undoManager)
    }

    /// Persists changes made to an existing equipment item in SwiftData.
    func updateEquipment(oldNodesSnapshot: [Equipment], undoManager: UndoManager?) {
        storageController.save()
        applyStateChange(oldNodes: oldNodesSnapshot, undoManager: undoManager)
    }
    
    // Call this function when project details already filled, and call in inside the sheet checkmark button
    func finalizeAndSaveSetup() {
        draftSetup.nodes = nodes
        storageController.save()
    }
    
    func discardSetup() {
        storageController.deleteSetup(draftSetup)
    }
    
    func deleteEquipment(nodeId: UUID, undoManager: UndoManager?) {
        // Snapshot BEFORE deleting
        let oldNodes = self.nodes.map { $0.clone() }
        
        if let index = nodes.firstIndex(where: { $0.id == nodeId }) {
            let nodeToDelete = nodes[index]
            nodes.remove(at: index)
            
            // NOTE: Call your specific SwiftData/Storage delete method here if you have one
            storageController.deleteEquipment(nodeToDelete)
        }
        
        storageController.save()
        applyStateChange(oldNodes: oldNodes, undoManager: undoManager)
    }
}
