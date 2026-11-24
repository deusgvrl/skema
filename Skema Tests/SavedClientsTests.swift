//
//  SavedClientsTests.swift
//  Skema Tests
//
//  The clients offered in Project Details.
//

import Foundation
import Testing
@testable import Skema_Photo

@MainActor
@Suite("Saved clients")
struct SavedClientsTests {
    private func store(_ client: String, savedDay: Double?, deleted: Bool = false, in storage: StorageController) {
        let setup = Setup(setupName: "Setup", client: client)
        setup.firstSavedDate = savedDay.map { Date(timeIntervalSince1970: $0 * 86_400) }
        setup.deletedDate = deleted ? Date(timeIntervalSince1970: 0) : nil
        storage.addSetup(setup)
    }

    private func clients(in storage: StorageController) -> [String] {
        let viewModel = ProjectDetailsViewModel(storageController: storage)
        viewModel.loadClients()
        return viewModel.savedClients
    }

    @Test("No setups gives no clients")
    func empty() {
        #expect(clients(in: StorageController(inMemory: true)).isEmpty)
    }

    @Test("Each client is listed once, A to Z")
    func sorted() {
        let storage = StorageController(inMemory: true)
        for client in ["Maison Noir", "Aesop", "Maison Noir", "brodo"] { store(client, savedDay: 1, in: storage) }
        #expect(clients(in: storage) == ["Aesop", "brodo", "Maison Noir"])
    }

    @Test("Different case or spaces is one client, spelled as in the newest setup")
    func sameClient() {
        let storage = StorageController(inMemory: true)
        store("aesop ", savedDay: 1, in: storage)
        store("Aesop", savedDay: 2, in: storage)
        #expect(clients(in: storage) == ["Aesop"])
    }

    @Test("Empty clients, drafts and Recently Deleted are left out")
    func leftOut() {
        let storage = StorageController(inMemory: true)
        store("", savedDay: 1, in: storage)
        store("   ", savedDay: 1, in: storage)
        store("Draft Client", savedDay: nil, in: storage)
        store("Deleted Client", savedDay: 1, deleted: true, in: storage)
        store("Aesop", savedDay: 1, in: storage)
        #expect(clients(in: storage) == ["Aesop"])
    }
}
