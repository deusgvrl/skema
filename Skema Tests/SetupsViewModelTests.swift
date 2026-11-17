//
//  SetupsViewModelTests.swift
//  Skema Tests
//
//  Created by Muhammad Dzakki Abdullah on 08/11/26.
//

import Foundation
import Testing
@testable import Final_Challenge_App

@MainActor
@Suite("Setups view model: scan entry")
struct SetupsViewModelTests {
    let settings = ScanGuideSettings(
        defaults: UserDefaults(suiteName: "SetupsViewModelTests.\(UUID().uuidString)")!
    )

    @Test("Starts on the empty state with nothing presented")
    func startsEmpty() {
        let settings = ScanGuideSettings()
        let testStorage = StorageController(inMemory: true)
        
        let viewModel = SetupsViewModel(
            scanGuide: settings,
            storageController: testStorage 
        )

        viewModel.fetchSetups()
        
        #expect(viewModel.showsEmptyState)
        #expect(!viewModel.isShowingScanGuide)
        #expect(!viewModel.isShowingScan)
    }

    @Test("+ shows the guide")
    func newSetupShowsGuide() {
        let viewModel = SetupsViewModel(scanGuide: settings)

        viewModel.newSetupTapped()

        #expect(viewModel.isShowingScanGuide)
        #expect(!viewModel.isShowingScan)
    }

    @Test("+ goes straight to the scan when the guide is hidden")
    func newSetupSkipsHiddenGuide() {
        settings.isHidden = true
        let viewModel = SetupsViewModel(scanGuide: settings)

        viewModel.newSetupTapped()

        #expect(!viewModel.isShowingScanGuide)
        #expect(viewModel.isShowingScan)
    }

    @Test("Start Scanning opens the scan once the sheet has closed")
    func startScanningOpensScanAfterSheetCloses() {
        let viewModel = SetupsViewModel(scanGuide: settings)
        viewModel.newSetupTapped()

        viewModel.startScanningTapped()

        #expect(!viewModel.isShowingScanGuide)
        #expect(!viewModel.isShowingScan)

        viewModel.scanGuideDismissed()

        #expect(viewModel.isShowingScan)
        #expect(!settings.isHidden)
    }

    @Test("Don’t Show Again hides the guide and opens the scan")
    func dontShowAgainHidesGuideAndScans() {
        let viewModel = SetupsViewModel(scanGuide: settings)
        viewModel.newSetupTapped()

        viewModel.dontShowAgainTapped()
        viewModel.scanGuideDismissed()

        #expect(settings.isHidden)
        #expect(viewModel.isShowingScan)
    }

    @Test("Closing the sheet with ✕ or a swipe does not start a scan")
    func swipeDismissDoesNotStartScan() {
        let viewModel = SetupsViewModel(scanGuide: settings)
        viewModel.newSetupTapped()

        viewModel.isShowingScanGuide = false // what SwiftUI does on ✕ or a swipe
        viewModel.scanGuideDismissed()

        #expect(!viewModel.isShowingScan)
        #expect(!settings.isHidden)
    }

    @Test("+ presents nothing extra while the guide or the scan is shown")
    func newSetupTappedIsIgnoredWhileSomethingIsShown() {
        // The scan is open: + must not put the guide over it.
        let scanning = SetupsViewModel(scanGuide: settings)
        scanning.newSetupTapped()
        scanning.startScanningTapped()
        scanning.scanGuideDismissed()

        scanning.newSetupTapped()

        #expect(scanning.isShowingScan)
        #expect(!scanning.isShowingScanGuide)

        // The guide is open: + must not open the scan under it.
        let guiding = SetupsViewModel(scanGuide: settings)
        guiding.newSetupTapped()
        settings.isHidden = true

        guiding.newSetupTapped()

        #expect(guiding.isShowingScanGuide)
        #expect(!guiding.isShowingScan)
    }

    @Test("An old scan request does not start a new scan")
    func requestIsClearedAfterUse() {
        let viewModel = SetupsViewModel(scanGuide: settings)
        viewModel.newSetupTapped()
        viewModel.startScanningTapped()
        viewModel.scanGuideDismissed()
        viewModel.isShowingScan = false // the user closes the scan

        viewModel.newSetupTapped()
        viewModel.isShowingScanGuide = false // swipe
        viewModel.scanGuideDismissed()

        #expect(!viewModel.isShowingScan)
    }

    @Test("Recent grouping puts setups in the right month section, newest first")
    func recentGroupingByMonth() {
        let storage = StorageController(inMemory: true)
        let newer = Setup(setupName: "Newer")
        newer.createdAt = Date()
        let older = Setup(setupName: "Older")
        older.createdAt = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        storage.addSetup(older)
        storage.addSetup(newer)
        let viewModel = SetupsViewModel(storageController: storage)

        viewModel.grouping = .recent

        #expect(viewModel.sections.count == 2)
        #expect(viewModel.sections[0].setups.map(\.setupName) == ["Newer"])
        #expect(viewModel.sections[1].setups.map(\.setupName) == ["Older"])
    }

    @Test("By Client grouping falls back to \"No Client\" for a blank client")
    func byClientGroupingFallsBackForBlankClient() {
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Orphan", client: "")
        storage.addSetup(setup)
        let viewModel = SetupsViewModel(storageController: storage)

        viewModel.grouping = .byClient

        #expect(viewModel.sections.map(\.title) == ["No Client"])
    }

    @Test("By Client caption is the month of the newest setup in that client group")
    func byClientCaptionIsNewestMonth() {
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Candle", client: "Aesop", project: "November catalog")
        storage.addSetup(setup)
        let viewModel = SetupsViewModel(storageController: storage)

        viewModel.grouping = .byClient

        #expect(viewModel.sections.first?.caption == setup.createdAt.formatted(.dateTime.month(.wide)))
    }

    @Test("Searching filters sections to only matching setups")
    func searchFiltersSections() {
        let storage = StorageController(inMemory: true)
        storage.addSetup(Setup(setupName: "Ring flash shoot", client: "Lulapin"))
        storage.addSetup(Setup(setupName: "Candle", client: "Aesop"))
        let viewModel = SetupsViewModel(storageController: storage)

        viewModel.searchText = "lulapin"

        #expect(viewModel.sections.flatMap(\.setups).map(\.setupName) == ["Ring flash shoot"])
        #expect(!viewModel.showsNoResults)
    }

    @Test("Searching with no match shows the no-results state, not an empty section list")
    func searchWithNoMatchShowsNoResults() {
        let storage = StorageController(inMemory: true)
        storage.addSetup(Setup(setupName: "Candle", client: "Aesop"))
        let viewModel = SetupsViewModel(storageController: storage)

        viewModel.searchText = "ring flash"

        #expect(viewModel.sections.isEmpty)
        #expect(viewModel.showsNoResults)
    }

    @Test("Deleting a setup soft-deletes it and undo restores it to the same grouping")
    func deleteThenUndoRestoresSetup() {
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Candle", client: "Aesop")
        storage.addSetup(setup)
        let viewModel = SetupsViewModel(storageController: storage)

        viewModel.deleteSetup(setup)
        #expect(viewModel.setups.isEmpty)
        #expect(storage.fetchDeletedSetups().map(\.setupName) == ["Candle"])

        viewModel.undoDelete()
        #expect(viewModel.setups.map(\.setupName) == ["Candle"])
        #expect(storage.fetchDeletedSetups().isEmpty)
    }
}
