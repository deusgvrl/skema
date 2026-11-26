//
//  SetupDetailViewModelTests.swift
//  Skema Tests
//

import Foundation
import Testing
@testable import Skema_Photo

@MainActor
@Suite("Setup detail view model: subtitle")
struct SetupDetailViewModelTests {
    @Test("Subtitle joins client and project with a dot, skipping blanks (Sketch R08)", arguments: [
        ("Aesop", "November catalog", "Aesop | November catalog"),
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

    @Test("The delete alert says a saved setup can be recovered, and a draft can’t")
    func deleteMessages() {
        let storage = StorageController(inMemory: true)
        let saved = Setup(setupName: "Candle")
        saved.firstSavedDate = Date()
        let draft = Setup()
        storage.addSetup(saved)
        storage.addSetup(draft)

        #expect(SetupDetailViewModel(setup: saved, storageController: storage).deleteMessage
            == "You can recover it from Recently Deleted for 30 days.")
        #expect(SetupDetailViewModel(setup: draft, storageController: storage).deleteMessage
            == "This draft will be deleted. This can’t be undone.")
    }
}
