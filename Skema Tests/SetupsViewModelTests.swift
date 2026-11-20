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
@testable import Final_Challenge_App

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
