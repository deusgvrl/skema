import Observation

/// State and actions for SetupsView.
/// Reads and writes data only through StorageController, and reloads on appear and after every change.
@Observable
final class SetupsViewModel {
    private(set) var setups: [Setup] = []
    var isShowingScanGuide = false
    var isShowingScan = false
    var showsEmptyState: Bool { setups.isEmpty }

    @ObservationIgnored private let scanGuide: ScanGuideSettings
    @ObservationIgnored private var scanRequested = false

    init(scanGuide: ScanGuideSettings = ScanGuideSettings()) {
           self.scanGuide = scanGuide
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

}
