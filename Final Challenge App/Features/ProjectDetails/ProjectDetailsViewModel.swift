import Foundation
import Observation

/// State and actions for ProjectDetailsView.
/// Reads and writes data only through StorageController, and reloads on appear and after every change.
@Observable
final class ProjectDetailsViewModel {
    @ObservationIgnored private let storageController: StorageController
    /// Injectable so tests can fix the date.
    @ObservationIgnored private let now: () -> Date
    /// Injectable so tests can force a failed save.
    @ObservationIgnored private let saveChanges: () throws -> Void

    enum SaveOutcome { case saved, nameMissing, failed }

    private(set) var showsNameRequired = false
    var isSaveFailedAlertPresented = false

    init(storageController: StorageController? = nil,
         now: @escaping () -> Date = { Date() },
         saveChanges: (() throws -> Void)? = nil) {
        self.storageController = storageController ?? StorageController.shared
        self.now = now
        let storage = self.storageController
        self.saveChanges = saveChanges ?? { try storage.trySave() }
    }

    /// A name with only spaces or new lines counts as empty.
    static func isNameValid(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func saveTapped(for setup: Setup) -> SaveOutcome {
        guard Self.isNameValid(setup.setupName) else {
            showsNameRequired = true
            return .nameMissing
        }
        let previousFirstSavedDate = setup.firstSavedDate
        if setup.firstSavedDate == nil {
            setup.firstSavedDate = now()
        }
        do {
            try saveChanges()
            return .saved
        } catch {
            // The first saved date belongs to the first successful save, so put it back.
            setup.firstSavedDate = previousFirstSavedDate
            isSaveFailedAlertPresented = true
            return .failed
        }
    }

    func nameChanged(_ name: String) {
        if Self.isNameValid(name) {
            showsNameRequired = false
        }
    }

    func handleClose(for setup: Setup) {
        if setup.firstSavedDate == nil {
            setup.firstSavedDate = now()
        }
        storageController.save()
    }
}
