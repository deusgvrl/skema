import Observation

/// State and actions for ScanView.
/// Reads and writes data only through StorageController, and reloads on appear and after every change.
@Observable
final class ScanViewModel {
    
    var draftSetup: Setup
    
    init() {
        self.draftSetup = Setup(setupName: "")
    }
    
    // call this function when scanning, adding an equipment when model catch equipment
    func addDraftEquipment(_ equipment: Equipment) {
        draftSetup.nodes.append(equipment)
    }
}
