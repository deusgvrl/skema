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
        for s in setups {
            print(" '\(s.setupName)' | Client: '\(s.client)' | Project: '\(s.project)' | Equipment total: '\(s.nodes.count)'")
        }
    }
    
    func deleteSetup(_ setup: Setup) {
        storageController.deleteSetup(setup)
        fetchSetups()
    }
}
