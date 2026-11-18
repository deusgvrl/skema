//
//  SetupsSearchTests.swift
//  Skema Tests
//
//  The bottom search field on Setups (Sketch R01, R01q), on top of the team's sections (A10-94).
//

import Foundation
import Testing
@testable import Final_Challenge_App

@MainActor
@Suite("Setups search")
struct SetupsSearchTests {
    func makeViewModel() -> SetupsViewModel {
        let storage = StorageController(inMemory: true)
        let saved = Date()
        let skincare = Setup(setupName: "Skincare / soft daylight", client: "Aesop", project: "November catalog")
        skincare.firstSavedDate = saved
        skincare.nodes.append(Equipment(category: .light, label: "L1", name: "Profoto D2", role: "Key"))
        let watch = Setup(setupName: "Watch / rim light", client: "Arloji")
        watch.firstSavedDate = saved
        storage.addSetup(skincare)
        storage.addSetup(watch)
        return SetupsViewModel(scanGuide: ScanGuideSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!),
                               storageController: storage)
    }

    @Test("Matches name, client, project and equipment, ignoring case and outer spaces", arguments: [
        ("soft", ["Skincare / soft daylight"]),
        ("ARLOJI", ["Watch / rim light"]),
        ("november", ["Skincare / soft daylight"]),
        ("profoto", ["Skincare / soft daylight"]),
        ("  key ", ["Skincare / soft daylight"]),
        ("", ["Skincare / soft daylight", "Watch / rim light"])
    ])
    func matches(query: String, expected: [String]) {
        let viewModel = makeViewModel()

        viewModel.searchText = query

        #expect(viewModel.searchedSetups.map(\.setupName).sorted() == expected)
    }

    @Test("Sections only hold matches, and no match shows the no-results state")
    func sectionsAndNoResults() {
        let viewModel = makeViewModel()

        viewModel.searchText = "rim"
        #expect(viewModel.recentSections.flatMap(\.setups).map(\.setupName) == ["Watch / rim light"])
        #expect(viewModel.showsNoResults == false)

        viewModel.searchText = "candle"
        #expect(viewModel.recentSections.isEmpty)
        #expect(viewModel.showsNoResults)
        #expect(viewModel.showsEmptyState == false)
    }
}
