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

    @Test("Subtitle joins client and project with a dot, skipping blanks (Sketch R08)", arguments: [
        ("Aesop", "November catalog", "Aesop · November catalog"),
        ("Aesop", "", "Aesop"),
        ("", "November catalog", "November catalog"),
        ("", "", "")
    ])
    func subtitle(client: String, project: String, expected: String) {
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Candle", client: client, project: project)
        storage.addSetup(setup)
        let viewModel = SetupDetailViewModel(setup: setup, storageController: storage)

        #expect(viewModel.formattedSubtitle == expected)
    }
}
