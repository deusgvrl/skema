//
//  RecentlyDeletedViewModelTests.swift
//  Skema Tests
//

import Foundation
import Testing
@testable import Final_Challenge_App

@MainActor
@Suite("Recently Deleted view model")
struct RecentlyDeletedViewModelTests {
    @Test("fetch purges expired setups first, then lists what remains")
    func fetchPurgesThenLists() {
        let storage = StorageController(inMemory: true)
        let expired = Setup(setupName: "Expired")
        storage.addSetup(expired)
        expired.deletedAt = Date().addingTimeInterval(-31 * 86_400)
        let recent = Setup(setupName: "Recent")
        storage.addSetup(recent)
        storage.softDeleteSetup(recent)
        let viewModel = RecentlyDeletedViewModel(storageController: storage)

        viewModel.fetch()

        #expect(viewModel.deletedSetups.map(\.setupName) == ["Recent"])
    }

    @Test("restore removes a setup from the deleted list")
    func restoreRemovesFromList() {
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Candle")
        storage.addSetup(setup)
        storage.softDeleteSetup(setup)
        let viewModel = RecentlyDeletedViewModel(storageController: storage)
        viewModel.fetch()

        viewModel.restore(setup)

        #expect(viewModel.deletedSetups.isEmpty)
        #expect(storage.fetchAllSetups().map(\.setupName) == ["Candle"])
    }

    @Test("daysLeft counts down from 30", arguments: [
        (0, 30), (1, 29), (29, 1), (30, 0), (31, 0)
    ])
    func daysLeftCountsDown(daysAgo: Int, expectedDaysLeft: Int) {
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Candle")
        storage.addSetup(setup)
        let now = Date()
        setup.deletedAt = now.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
        let viewModel = RecentlyDeletedViewModel(storageController: storage)

        #expect(viewModel.daysLeft(for: setup, now: now) == expectedDaysLeft)
    }
}
