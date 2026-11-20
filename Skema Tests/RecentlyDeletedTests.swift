import Testing
import SwiftData
import Foundation
@testable import Final_Challenge_App

@Suite("Recently Deleted (A10-95)")
@MainActor
struct RecentlyDeletedTests {

    /// Jakarta calendar, used both to build the dates and as the injected calendar,
    /// so the tests do not depend on the machine's time zone.
    private static let jakarta: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return calendar
    }()

    private let calendar = RecentlyDeletedTests.jakarta

    private func date(day: Int, month: Int = 11, year: Int = 2026, hour: Int = 10, minute: Int = 0) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return RecentlyDeletedTests.jakarta.date(from: parts)!
    }

    /// Stores a setup. A nil `saved` date makes it a draft.
    private func store(_ name: String, saved: Date?, deleted: Date? = nil, in storage: StorageController) -> Setup {
        let setup = Setup(setupName: name)
        setup.firstSavedDate = saved
        setup.deletedDate = deleted
        storage.addSetup(setup)
        return setup
    }

    private func setupsViewModel(_ storage: StorageController, now: Date) -> SetupsViewModel {
        SetupsViewModel(storageController: storage, now: { now })
    }

    private func recentlyDeletedViewModel(_ storage: StorageController, now: Date) -> RecentlyDeletedViewModel {
        RecentlyDeletedViewModel(storageController: storage, now: { now }, calendar: calendar)
    }

    /// Reads from a fresh context, so it only sees what was really saved to the store.
    private func freshContext(_ storage: StorageController) -> ModelContext {
        ModelContext(storage.container)
    }

    private func freshRecentlyDeleted(_ storage: StorageController) throws -> [Setup] {
        try freshContext(storage).fetch(FetchDescriptor<Setup>()).filter { $0.deletedDate != nil }
    }

    @Test("Case 1: deleting a saved setup moves it to Recently Deleted with 30 days left")
    func deleteMovesToRecentlyDeleted() throws {
        // Arrange
        let storage = StorageController(inMemory: true)
        let setup = store("Shoe shoot", saved: date(day: 1, month: 10), in: storage)
        let viewModel = setupsViewModel(storage, now: date(day: 2))

        // Act
        viewModel.deleteTapped(setup)
        viewModel.confirmDelete()

        // Assert
        let recentlyDeleted = recentlyDeletedViewModel(storage, now: date(day: 2))
        recentlyDeleted.load()
        #expect(!viewModel.setups.contains { $0.setupName == "Shoe shoot" }, "It should leave the main list.")
        #expect(recentlyDeleted.setups.map(\.setupName) == ["Shoe shoot"])
        #expect(recentlyDeleted.daysLeftText(for: setup) == "30 days left")
        #expect(try freshRecentlyDeleted(storage).map(\.setupName) == ["Shoe shoot"], "The delete must be saved.")
    }

    @Test("Case 2: Undo brings the setup back")
    func undoBringsBack() throws {
        // Arrange
        let storage = StorageController(inMemory: true)
        let setup = store("Shoe shoot", saved: date(day: 1, month: 10), in: storage)
        let viewModel = setupsViewModel(storage, now: date(day: 2))
        viewModel.deleteTapped(setup)
        viewModel.confirmDelete()

        // Act
        viewModel.undoDelete()

        // Assert
        #expect(viewModel.setups.contains { $0.setupName == "Shoe shoot" }, "It should be back in the main list.")
        #expect(try freshRecentlyDeleted(storage).isEmpty, "Nothing should stay in Recently Deleted.")
    }

    @Test("Case 3: Cancel keeps the setup where it was")
    func cancelKeepsSetup() throws {
        // Arrange
        let storage = StorageController(inMemory: true)
        let setup = store("Shoe shoot", saved: date(day: 1, month: 10), in: storage)
        let viewModel = setupsViewModel(storage, now: date(day: 2))

        // Act
        viewModel.deleteTapped(setup)
        viewModel.cancelDelete()

        // Assert
        #expect(viewModel.setups.contains { $0.setupName == "Shoe shoot" })
        #expect(viewModel.setupPendingDelete == nil)
        #expect(setup.deletedDate == nil)
        #expect(try freshRecentlyDeleted(storage).isEmpty)
    }

    @Test("Case 4: Recover puts the setup back under its first saved month")
    func recoverKeepsFirstSavedMonth() throws {
        // Arrange
        let storage = StorageController(inMemory: true)
        let firstSaved = date(day: 2, month: 10)
        let setup = store("Shoe shoot", saved: firstSaved, deleted: date(day: 2), in: storage)
        let recentlyDeleted = recentlyDeletedViewModel(storage, now: date(day: 10))
        recentlyDeleted.load()

        // Act
        recentlyDeleted.recover(setup)

        // Assert
        let viewModel = setupsViewModel(storage, now: date(day: 10))
        let october = viewModel.recentSections.first { $0.title == "October 2026" }
        #expect(october?.setups.map(\.setupName) == ["Shoe shoot"])
        #expect(setup.firstSavedDate == firstSaved, "Recover must not change the first saved date.")
        #expect(try freshRecentlyDeleted(storage).isEmpty)
    }

    @Test("Case 5: days left count down by calendar day")
    func daysLeftText() {
        // Arrange
        let storage = StorageController(inMemory: true)
        let setup = store("Shoe shoot", saved: date(day: 1, month: 10), deleted: date(day: 2), in: storage)

        // Act
        let onDec1 = recentlyDeletedViewModel(storage, now: date(day: 1, month: 12))
        let onDec2 = recentlyDeletedViewModel(storage, now: date(day: 2, month: 12))

        // Assert
        #expect(onDec1.daysLeftText(for: setup) == "1 day left")
        #expect(onDec2.daysLeftText(for: setup) == "0 days left")
    }

    @Test("Case 6: the last day (2 Dec) still keeps the setup")
    func lastDayKeepsSetup() throws {
        // Arrange
        let storage = StorageController(inMemory: true)
        _ = store("Shoe shoot", saved: date(day: 1, month: 10), deleted: date(day: 2), in: storage)

        // Act
        storage.purgeExpiredSetups(now: date(day: 2, month: 12, hour: 23), calendar: calendar)

        // Assert
        #expect(try freshRecentlyDeleted(storage).count == 1)
    }

    @Test("Case 7: from 3 Dec the purge removes the setup, its equipment and its photos")
    func purgeRemovesEverything() throws {
        // Arrange
        let storage = StorageController(inMemory: true)
        let setup = store("Shoe shoot", saved: date(day: 1, month: 10), deleted: date(day: 2), in: storage)
        storage.addEquipment(Equipment(category: .light, name: "Key light"), to: setup)
        storage.addReferenceImage(ReferenceImage(imageData: Data([1, 2, 3])), to: setup)

        // Act
        storage.purgeExpiredSetups(now: date(day: 3, month: 12, hour: 0, minute: 30), calendar: calendar)

        // Assert
        let context = freshContext(storage)
        #expect(try context.fetch(FetchDescriptor<Setup>()).isEmpty, "The setup should be gone.")
        #expect(try context.fetch(FetchDescriptor<Equipment>()).isEmpty, "Its equipment should be gone.")
        #expect(try context.fetch(FetchDescriptor<ReferenceImage>()).isEmpty, "Its photos should be gone.")
    }

    @Test("Case 8: newest deleted first")
    func newestDeletedFirst() {
        // Arrange
        let storage = StorageController(inMemory: true)
        _ = store("Bag", saved: date(day: 1, month: 10), deleted: date(day: 2), in: storage)
        _ = store("Watch", saved: date(day: 1, month: 10), deleted: date(day: 5), in: storage)
        let viewModel = recentlyDeletedViewModel(storage, now: date(day: 6))

        // Act
        viewModel.load()

        // Assert
        #expect(viewModel.setups.map(\.setupName) == ["Watch", "Bag"])
    }

    @Test("Case 9: a deleted setup is hidden from Recent and By Client")
    func deletedSetupIsHiddenFromLists() {
        // Arrange
        let storage = StorageController(inMemory: true)
        _ = store("Kept", saved: date(day: 1, month: 10), in: storage)
        _ = store("Gone", saved: date(day: 1, month: 10), deleted: date(day: 2), in: storage)

        // Act
        let viewModel = setupsViewModel(storage, now: date(day: 3))

        // Assert
        let recentNames = viewModel.recentSections.flatMap(\.setups).map(\.setupName)
        let clientNames = viewModel.clientGroups.flatMap(\.sections).flatMap(\.setups).map(\.setupName)
        #expect(recentNames == ["Kept"])
        #expect(clientNames == ["Kept"])
    }

    @Test("Case 10: a draft is removed for good, with no Undo")
    func draftIsHardDeleted() throws {
        // Arrange
        let storage = StorageController(inMemory: true)
        let draft = store("New Setup", saved: nil, in: storage)
        let viewModel = setupsViewModel(storage, now: date(day: 2))

        // Act
        viewModel.deleteTapped(draft)
        viewModel.confirmDelete()

        // Assert
        let recentlyDeleted = recentlyDeletedViewModel(storage, now: date(day: 2))
        recentlyDeleted.load()
        #expect(viewModel.setups.isEmpty)
        #expect(recentlyDeleted.setups.isEmpty)
        #expect(try freshContext(storage).fetch(FetchDescriptor<Setup>()).isEmpty, "No setup should be left at all.")
        #expect(viewModel.lastDeleted == nil, "A draft has no Undo.")
    }

    @Test("Case 11: nothing deleted shows the empty state")
    func emptyState() {
        // Arrange
        let storage = StorageController(inMemory: true)
        let viewModel = recentlyDeletedViewModel(storage, now: date(day: 2))

        // Act
        viewModel.load()

        // Assert
        #expect(viewModel.showsEmptyState)
    }
}
