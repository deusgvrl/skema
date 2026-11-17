import Foundation
import Observation

/// State and actions for ProjectDetailsView.
/// Reads and writes data only through StorageController, and reloads on appear and after every change.
@Observable
final class ProjectDetailsViewModel {
    @ObservationIgnored private let storageController: StorageController
    /// Injectable so tests can fix the date.
    @ObservationIgnored private let now: () -> Date

    init(storageController: StorageController? = nil, now: @escaping () -> Date = { Date() }) {
        self.storageController = storageController ?? StorageController.shared
        self.now = now
    }

    func handleClose(for setup: Setup) {
        if setup.firstSavedDate == nil {
            setup.firstSavedDate = now()
        }
        storageController.save()
    }
}
