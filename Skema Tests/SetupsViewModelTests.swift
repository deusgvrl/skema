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
}
