import Testing
import SwiftData
@testable import Final_Challenge_App
import Foundation

@Suite("Save feedback (A10-97)")
@MainActor
struct SaveFeedbackTests {

    private struct TestSaveError: Error {}

    /// Reads from a fresh context, so it only sees what was really saved to the store.
    private func savedSetups(in storage: StorageController) throws -> [Setup] {
        try ModelContext(storage.container).fetch(FetchDescriptor<Setup>())
    }

    @Test("Case 1: Save with an empty name shows Required and saves nothing")
    func emptyNameIsRejected() throws {
        // Arrange
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "")
        storage.addSetup(setup)
        let viewModel = ProjectDetailsViewModel(storageController: storage)

        // Act
        let outcome = viewModel.saveTapped(for: setup)

        // Assert
        #expect(outcome == .nameMissing, "An empty name should not save.")
        #expect(viewModel.showsNameRequired, "Required should show after the Save tap.")
        #expect(try savedSetups(in: storage).first?.firstSavedDate == nil, "Nothing should be saved by the user.")
    }

    @Test("Case 2: Save with only spaces counts as an empty name")
    func spacesOnlyNameIsRejected() throws {
        // Arrange
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "   ")
        storage.addSetup(setup)
        let viewModel = ProjectDetailsViewModel(storageController: storage)

        // Act
        let outcome = viewModel.saveTapped(for: setup)

        // Assert
        #expect(outcome == .nameMissing, "Spaces alone should not save.")
        #expect(viewModel.showsNameRequired, "Required should show after the Save tap.")
        #expect(try savedSetups(in: storage).first?.firstSavedDate == nil, "Nothing should be saved by the user.")
    }

    @Test("Case 3: typing a name clears Required")
    func typingClearsRequired() {
        // Arrange
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "")
        storage.addSetup(setup)
        let viewModel = ProjectDetailsViewModel(storageController: storage)
        _ = viewModel.saveTapped(for: setup)
        #expect(viewModel.showsNameRequired, "Required must be showing before the user types.")

        // Act
        setup.setupName = "S"
        viewModel.nameChanged("S")

        // Assert
        #expect(!viewModel.showsNameRequired, "Required should go away once the name has a character.")
    }

    @Test("Case 4: Required does not show before any Save tap")
    func requiredHiddenOnOpen() {
        // Arrange and Act
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "")
        storage.addSetup(setup)
        let viewModel = ProjectDetailsViewModel(storageController: storage)

        // Assert
        #expect(!viewModel.showsNameRequired, "A new screen should not show Required.")
    }

    @Test("Case 5: Save with a name saves and reports success")
    func validNameSaves() throws {
        // Arrange
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Shoe shoot")
        storage.addSetup(setup)
        let viewModel = ProjectDetailsViewModel(storageController: storage)

        // Act
        let outcome = viewModel.saveTapped(for: setup)

        // Assert
        #expect(outcome == .saved, "A valid name should save.")
        #expect(!viewModel.showsNameRequired)
        #expect(!viewModel.isSaveFailedAlertPresented)
        let fetched = try savedSetups(in: storage).first
        #expect(fetched?.setupName == "Shoe shoot", "The name should be in the store.")
        #expect(fetched?.firstSavedDate != nil, "The first Save should set the first saved date.")
    }

    @Test("Case 6: a failed save keeps the typed details and the alert shows")
    func failedSaveKeepsDetails() {
        // Arrange
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Shoe shoot")
        storage.addSetup(setup)
        let viewModel = ProjectDetailsViewModel(storageController: storage, saveChanges: { throw TestSaveError() })
        setup.notes = "My notes"

        // Act
        let outcome = viewModel.saveTapped(for: setup)

        // Assert
        #expect(outcome == .failed, "A throwing save should report failure.")
        #expect(viewModel.isSaveFailedAlertPresented, "The Save Failed alert should show.")
        #expect(setup.setupName == "Shoe shoot", "The typed name should be kept.")
        #expect(setup.notes == "My notes", "The typed notes should be kept.")
        #expect(setup.firstSavedDate == nil, "The first saved date belongs to the first successful save.")
    }
}
