//
//  SetupDetailViewModelTests.swift
//  Skema Tests
//

import Foundation
import Testing
@testable import Final_Challenge_App

@MainActor
@Suite("Setup detail view model: delete")
struct SetupDetailViewModelTests {
    @Test("Deleting from setup detail moves the setup to Recently Deleted")
    func deleteIsSoft() {
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Candle")
        storage.addSetup(setup)
        let viewModel = SetupDetailViewModel(setup: setup, storageController: storage)
        var completed = false

        viewModel.deleteSetup { completed = true }

        #expect(completed)
        #expect(storage.fetchAllSetups().isEmpty)
        #expect(storage.fetchDeletedSetups().map(\.setupName) == ["Candle"])
    }
}
