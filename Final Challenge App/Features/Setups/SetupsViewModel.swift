import Foundation
import Observation

/// State and actions for SetupsView.
/// Reads and writes data only through StorageController, and reloads on appear and after every change.
@MainActor
@Observable
final class SetupsViewModel {
    
    var setups: [Setup] = []
    var isShowingScanGuide = false
    var isShowingScan = false
    var showsEmptyState: Bool { setups.isEmpty }
    /// The setup waiting for the user to confirm the delete alert.
    var setupPendingDelete: Setup?
    /// The setup just moved to Recently Deleted, so the View can offer Undo. Drafts never set it.
    var lastDeleted: Setup?
    /// Whether the "Setup saved" toast shows.
    private(set) var showsSavedToast = false
    /// Whether to show the Recently Deleted row.
    private(set) var hasRecentlyDeleted = false
    var grouping: SetupsGrouping = .recent
    /// The bottom search field (Sketch R01): filters by setup name, client, project and equipment.
    var searchText = ""
    var showsNoResults: Bool { !searchText.isEmpty && !setups.isEmpty && searchedSetups.isEmpty }
    var recentSections: [SetupSection] { SetupSections.recent(from: searchedSetups) }
    var clientGroups: [ClientGroup] { SetupSections.byClient(from: searchedSetups) }

    /// The setups matching `searchText`, or all of them when it is empty.
    var searchedSetups: [Setup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return setups }
        return setups.filter { setup in
            if setup.setupName.lowercased().contains(query) { return true }
            if setup.client.lowercased().contains(query) { return true }
            if setup.project.lowercased().contains(query) { return true }
            return setup.nodes.contains { node in
                node.name.lowercased().contains(query) || node.role.lowercased().contains(query)
            }
        }
    }

    @ObservationIgnored private let scanGuide: ScanGuideSettings
    @ObservationIgnored private let storageController: StorageController
    @ObservationIgnored private var scanRequested = false
    @ObservationIgnored private let now: () -> Date

    init(scanGuide: ScanGuideSettings? = nil,
         storageController: StorageController? = nil,
         now: @escaping () -> Date = { Date() }) {
        self.now = now
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
        self.hasRecentlyDeleted = !storageController.fetchRecentlyDeleted().isEmpty
    }

    /// The alert text: saved setups can be recovered for 30 days, drafts cannot.
    func deleteMessage(for setup: Setup) -> String {
        setup.firstSavedDate == nil
            ? "This draft will be deleted. This can't be undone."
            : "This setup will move to Recently Deleted for \(RecentlyDeleted.keepDays) days."
    }

    func deleteTapped(_ setup: Setup) {
        setupPendingDelete = setup
    }

    func cancelDelete() {
        setupPendingDelete = nil
    }

    func confirmDelete() {
        guard let setup = setupPendingDelete else { return }
        if setup.firstSavedDate == nil {
            // A draft was never saved by the user, so it skips Recently Deleted and has no Undo.
            storageController.deleteSetup(setup)
            lastDeleted = nil
        } else {
            storageController.moveToRecentlyDeleted(setup, at: now())
            lastDeleted = setup
        }
        setupPendingDelete = nil
        fetchSetups()
    }

    func undoDelete() {
        guard let setup = lastDeleted else { return }
        storageController.recover(setup)
        lastDeleted = nil
        fetchSetups()
    }

    func setupSaved() {
        showsSavedToast = true
    }

    func dismissSavedToast() {
        showsSavedToast = false
    }

    func dismissUndo() {
        lastDeleted = nil
    }
}
