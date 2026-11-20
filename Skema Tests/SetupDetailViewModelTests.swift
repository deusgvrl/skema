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
