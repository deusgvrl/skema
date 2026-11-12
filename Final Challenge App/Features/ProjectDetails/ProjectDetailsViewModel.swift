import Observation

/// State and actions for ProjectDetailsView.
/// Reads and writes data only through StorageController, and reloads on appear and after every change.
@Observable
final class ProjectDetailsViewModel {
    
    func handleClose() {
        StorageController.shared.save()
    }
}
