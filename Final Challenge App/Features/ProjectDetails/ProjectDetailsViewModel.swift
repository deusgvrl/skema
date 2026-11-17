import Foundation
import Observation

/// State and actions for ProjectDetailsView (Sketch R07, R07e, R07f).
/// The fields are a copy of the setup's values, written back only on ✓ (or when going back to the
/// diagram), so Cancel in "Edit details" leaves the saved setup untouched.
@Observable
final class ProjectDetailsViewModel {
    static let storageFullMessage =
        "Your iPhone storage is full. Free up some space and try again. Your details are still here."
    static let generalFailureMessage =
        "Something went wrong while saving. Try again. Your details are still here."

    var name: String {
        didSet { hasEditedName = true }
    }
    var client: String
    var project: String
    var notes: String
    /// The message for "Couldn't Save Setup", or nil when the last save worked.
    private(set) var saveFailure: String?

    @ObservationIgnored private let setup: Setup
    @ObservationIgnored private let saveChanges: () throws -> Void
    private var hasEditedName = false

    init(setup: Setup, saveChanges: (() throws -> Void)? = nil) {
        self.setup = setup
        self.name = setup.setupName
        self.client = setup.client
        self.project = setup.project
        self.notes = setup.notes
        self.saveChanges = saveChanges ?? { try StorageController.shared.saveChanges() }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// ✓ is enabled only with a name.
    var canSave: Bool { !trimmedName.isEmpty }

    /// "Add a name to save this setup." — only after the user cleared the name, not on arrival (R07e).
    var showsNameError: Bool { hasEditedName && !canSave }

    /// ✓ / Try Again. Returns true when the setup was saved.
    @discardableResult
    func save() -> Bool {
        guard canSave else { return false }
        applyWithoutSaving()
        do {
            try saveChanges()
            saveFailure = nil
            return true
        } catch {
            saveFailure = Self.isOutOfSpace(error) ? Self.storageFullMessage : Self.generalFailureMessage
            return false
        }
    }

    /// Writes the fields to the setup without saving, e.g. when going back to the diagram.
    func applyWithoutSaving() {
        setup.setupName = trimmedName
        setup.client = client.trimmingCharacters(in: .whitespacesAndNewlines)
        setup.project = project.trimmingCharacters(in: .whitespacesAndNewlines)
        setup.notes = notes
    }

    private static func isOutOfSpace(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isOutOfSpace(underlying)
        }
        return false
    }
}
