import Foundation
import Observation

enum SetupsGrouping {
    case recent
    case byClient
}

struct SetupSection: Identifiable {
    let id: String
    let title: String
    let caption: String?
    let setups: [Setup]
}

/// State and actions for SetupsView.
/// Reads and writes data only through StorageController, and reloads on appear and after every change.
@MainActor
@Observable
final class SetupsViewModel {

    var setups: [Setup] = []
    var isShowingScanGuide = false
    var isShowingScan = false
    var grouping: SetupsGrouping = .recent
    var searchText: String = ""
    var lastDeleted: Setup?
    var showsEmptyState: Bool { searchText.isEmpty && setups.isEmpty }
    var showsNoResults: Bool { !searchText.isEmpty && sections.isEmpty }

    var sections: [SetupSection] {
        let filtered = filteredSetups()
        switch grouping {
        case .recent:
            return recentSections(for: filtered)
        case .byClient:
            return byClientSections(for: filtered)
        }
    }

    @ObservationIgnored private let scanGuide: ScanGuideSettings
    @ObservationIgnored private let storageController: StorageController
    @ObservationIgnored private var scanRequested = false

    init(scanGuide: ScanGuideSettings? = nil,
         storageController: StorageController? = nil) {
        self.scanGuide = scanGuide ?? ScanGuideSettings()
        self.storageController = storageController ?? StorageController.shared
        self.fetchSetups()
    }
    
    func newSetupTapped() {
        guard !isShowingScanGuide, !isShowingScan else { return }

        if scanGuide.isHidden {
            isShowingScan = true
        } else {
            isShowingScanGuide = true
        }
    }

    func startScanningTapped() {
        scanRequested = true
        isShowingScanGuide = false
    }

    func dontShowAgainTapped() {
        scanGuide.isHidden = true
        startScanningTapped()
    }

    func scanGuideDismissed() {
        guard scanRequested else { return }
        scanRequested = false
        isShowingScan = true
    }
    
    func fetchSetups() {
        self.setups = storageController.fetchAllSetups()
        print("[SwiftData Test] Fetched \(setups.count) setup(s):")
        for setup in setups {
            print(" '\(setup.setupName)' | Client: '\(setup.client)' | Project: '\(setup.project)' | Equipment total: '\(setup.nodes.count)'")
        }
    }
    
    func deleteSetup(_ setup: Setup) {
        storageController.softDeleteSetup(setup)
        lastDeleted = setup
        fetchSetups()
    }

    func undoDelete() {
        guard let setup = lastDeleted else { return }
        storageController.restoreSetup(setup)
        lastDeleted = nil
        fetchSetups()
    }

    private func filteredSetups() -> [Setup] {
        guard !searchText.isEmpty else { return setups }
        let query = searchText.lowercased()
        return setups.filter { setup in
            if setup.setupName.lowercased().contains(query) { return true }
            if setup.client.lowercased().contains(query) { return true }
            if setup.project.lowercased().contains(query) { return true }
            return setup.nodes.contains { node in
                node.name.lowercased().contains(query) || node.role.lowercased().contains(query)
            }
        }
    }

    private func recentSections(for setups: [Setup]) -> [SetupSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: setups) { setup in
            calendar.dateInterval(of: .month, for: setup.createdAt)?.start ?? setup.createdAt
        }
        let currentMonthStart = calendar.dateInterval(of: .month, for: Date())?.start

        return grouped.keys.sorted(by: >).map { monthStart in
            let setupsInMonth = (grouped[monthStart] ?? []).sorted(by: newestFirst)
            let title = monthName(monthStart)
            let caption = (monthStart == currentMonthStart) ? "This month" : nil
            return SetupSection(
                id: "recent-\(monthStart.timeIntervalSince1970)",
                title: title,
                caption: caption,
                setups: setupsInMonth
            )
        }
    }

    private func byClientSections(for setups: [Setup]) -> [SetupSection] {
        let noClientTitle = "No Client"
        let grouped = Dictionary(grouping: setups) { setup -> String in
            let client = setup.client.trimmingCharacters(in: .whitespacesAndNewlines)
            return client.isEmpty ? noClientTitle : client
        }
        let sortedTitles = grouped.keys.sorted { lhs, rhs in
            if lhs == noClientTitle { return false }
            if rhs == noClientTitle { return true }
            return lhs < rhs
        }

        return sortedTitles.map { title in
            let setupsForClient = (grouped[title] ?? []).sorted(by: newestFirst)
            let caption = setupsForClient.first.map { monthName($0.createdAt) }
            return SetupSection(id: "client-\(title)", title: title, caption: caption, setups: setupsForClient)
        }
    }

    /// Newest first; setups saved at the same moment (e.g. all given the same `createdAt`
    /// by the migration that added it) fall back to name order so the list is stable.
    private func newestFirst(_ lhs: Setup, _ rhs: Setup) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.setupName.localizedStandardCompare(rhs.setupName) == .orderedAscending
    }

    private func monthName(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            return date.formatted(.dateTime.month(.wide))
        }
        return date.formatted(.dateTime.month(.wide).year())
    }
}
