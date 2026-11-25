//
//  SetupsViewModelTests.swift
//  Skema Tests
//
//  Created by Muhammad Dzakki Abdullah on 08/11/26.
//
//  + opens the scan straight away: the tutorial now runs inside the scan (Sketch UT Review T01–T10).
//

import Foundation
import Testing
@testable import Skema_Photo

@MainActor
@Suite("Setups view model: scan entry")
struct SetupsViewModelTests {
    @Test("Starts on the empty state with nothing presented")
    func startsEmpty() {
        let viewModel = SetupsViewModel(storageController: StorageController(inMemory: true))

        viewModel.fetchSetups()

        #expect(viewModel.showsEmptyState)
        #expect(!viewModel.isShowingScan)
    }

    @Test("+ opens the scan straight away, with no sheet first")
    func newSetupOpensScan() {
        let viewModel = SetupsViewModel(storageController: StorageController(inMemory: true))

        viewModel.newSetupTapped()

        #expect(viewModel.isShowingScan)
    }

    @Test("+ again while the scan is open changes nothing")
    func newSetupWhileScanning() {
        let viewModel = SetupsViewModel(storageController: StorageController(inMemory: true))
        viewModel.newSetupTapped()

        viewModel.newSetupTapped()

        #expect(viewModel.isShowingScan)
    }
}

@MainActor
@Suite("Setups view model: copy (audit 24–25 Nov)")
struct SetupsCopyTests {
    private func viewModel(grouping: SetupsGrouping = .recent) -> SetupsViewModel {
        let viewModel = SetupsViewModel(storageController: StorageController(inMemory: true))
        viewModel.grouping = grouping
        return viewModel
    }

    @Test("The delete alert says a saved setup can be recovered, and a draft can’t")
    func deleteMessages() {
        let saved = Setup(setupName: "Shoe shoot")
        saved.firstSavedDate = Date()

        #expect(viewModel().deleteMessage(for: saved) == "You can recover it from Recently Deleted for 30 days.")
        #expect(viewModel().deleteMessage(for: Setup()) == "This draft will be deleted. This can’t be undone.")
    }

    @Test("A card shows the client by month and the project by client, with no light count", arguments: [
        (SetupsGrouping.recent, "Aesop"), (.byClient, "Spring catalog")
    ])
    func cardSubtitle(grouping: SetupsGrouping, expected: String) {
        let setup = Setup(setupName: "Hero shot", client: " Aesop ", project: "Spring catalog ")
        setup.nodes = [Equipment(category: .light, name: "Light 1")]

        #expect(viewModel(grouping: grouping).cardSubtitle(for: setup) == expected)
    }

    @Test("A card with no client or project has no subtitle", arguments: [SetupsGrouping.recent, .byClient])
    func cardSubtitleEmpty(grouping: SetupsGrouping) {
        let setup = Setup(setupName: "Hero shot", client: "  ", project: "")
        setup.nodes = [Equipment(category: .light, name: "Light 1")]

        #expect(viewModel(grouping: grouping).cardSubtitle(for: setup).isEmpty)
    }
}
