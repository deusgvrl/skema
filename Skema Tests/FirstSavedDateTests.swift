import Testing
import SwiftData
@testable import Skema_Photo
import Foundation

@Suite("First saved date (A10-93)")
@MainActor
struct FirstSavedDateTests {

    /// Fixed dates in Jakarta time so the tests do not depend on the machine's time zone.
    private static func jakartaDate(day: Int, month: Int = 11, year: Int = 2026) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        let parts = DateComponents(year: year, month: month, day: day, hour: 10)
        return calendar.date(from: parts)!
    }

    private let nov2 = FirstSavedDateTests.jakartaDate(day: 2)
    private let nov5 = FirstSavedDateTests.jakartaDate(day: 5)

    /// Reads from a fresh context, so it only sees what was really saved to the store.
    private func savedSetups(in storage: StorageController) throws -> [Setup] {
        try ModelContext(storage.container).fetch(FetchDescriptor<Setup>())
    }

    @Test("Case 1: the first Save sets the first saved date")
    func firstSaveSetsDate() throws {
        // Arrange
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Never saved")
        storage.addSetup(setup)
        let viewModel = ProjectDetailsViewModel(storageController: storage, now: { nov2 })

        // Act
        viewModel.handleClose(for: setup)

        // Assert
        #expect(setup.firstSavedDate == nov2, "The first Save should set the date to 2 Nov 2026.")
        #expect(try savedSetups(in: storage).first?.firstSavedDate == nov2, "The date should be kept in the store.")
    }

    @Test("Case 2: saving again keeps the first saved date")
    func secondSaveKeepsDate() throws {
        // Arrange
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Saved twice")
        storage.addSetup(setup)
        ProjectDetailsViewModel(storageController: storage, now: { nov2 }).handleClose(for: setup)
        let laterViewModel = ProjectDetailsViewModel(storageController: storage, now: { nov5 })

        // Act
        laterViewModel.handleClose(for: setup)

        // Assert
        #expect(setup.firstSavedDate == nov2, "A second Save on 5 Nov must keep 2 Nov.")
        #expect(try savedSetups(in: storage).first?.firstSavedDate == nov2, "The stored date must still be 2 Nov.")
    }

    @Test("Case 3: editing notes and saving keeps the first saved date")
    func editingNotesKeepsDate() throws {
        // Arrange
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Edited later", notes: "Old notes")
        storage.addSetup(setup)
        ProjectDetailsViewModel(storageController: storage, now: { nov2 }).handleClose(for: setup)
        let laterViewModel = ProjectDetailsViewModel(storageController: storage, now: { nov5 })

        // Act
        setup.notes = "New notes"
        laterViewModel.handleClose(for: setup)

        // Assert
        let fetched = try savedSetups(in: storage).first
        #expect(fetched?.firstSavedDate == nov2, "Editing notes must not change the first saved date.")
        #expect(fetched?.notes == "New notes", "The new notes should be saved.")
    }

    @Test("Case 4: a new setup under review has no first saved date")
    func unsavedReviewHasNoDate() throws {
        // Arrange and Act: the review stores a new draft the way the app does after a scan
        let storage = StorageController(inMemory: true)
        let review = ReviewViewModel(storageController: storage)

        // Assert
        #expect(review.draftSetup.firstSavedDate == nil, "The draft has not been saved by the user yet.")
        #expect(try savedSetups(in: storage).first?.firstSavedDate == nil, "The stored draft should have no date.")
    }

    @Test("Case 5: an old setup with no date still loads")
    func oldSetupWithoutDateLoads() throws {
        // The real old-schema upgrade (store written without the field) was checked by hand on the Mac on 17 Nov.
        // This test guards that a setup with no date still loads from a store on disk.

        // Arrange
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FirstSavedDateTests-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }
        let schema = Schema([Setup.self, Equipment.self, ReferenceImage.self])
        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        // Act: write with container A, then load with a new container B
        do {
            let containerA = try ModelContainer(for: schema, configurations: [configuration])
            containerA.mainContext.insert(Setup(setupName: "Old setup"))
            try containerA.mainContext.save()
        }
        let containerB = try ModelContainer(for: schema, configurations: [configuration])
        let loaded = try ModelContext(containerB).fetch(FetchDescriptor<Setup>())

        // Assert
        #expect(loaded.count == 1, "The old setup should load.")
        #expect(loaded.first?.setupName == "Old setup")
        #expect(loaded.first?.firstSavedDate == nil, "An old setup has no first saved date.")
    }
}
