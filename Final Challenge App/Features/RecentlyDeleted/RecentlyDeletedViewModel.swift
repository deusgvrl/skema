import Observation
import Foundation

/// State and actions for RecentlyDeletedView (A10-95).
/// Reads and writes data only through StorageController.
@MainActor
@Observable
final class RecentlyDeletedViewModel {
    var setups: [Setup] = []
    /// The setup just recovered, so the View can show the "Setup recovered" toast.
    var lastRecovered: Setup?
    var showsEmptyState: Bool { setups.isEmpty }

    @ObservationIgnored private let storageController: StorageController
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    init(storageController: StorageController? = nil,
         now: @escaping () -> Date = { Date() },
         calendar: Calendar = .current) {
        self.storageController = storageController ?? StorageController.shared
        self.now = now
        self.calendar = calendar
    }

    /// Newest deleted first.
    func load() {
        setups = storageController.fetchRecentlyDeleted()
            .sorted { ($0.deletedDate ?? .distantPast) > ($1.deletedDate ?? .distantPast) }
    }

    func daysLeftText(for setup: Setup) -> String {
        guard let deletedDate = setup.deletedDate else { return "" }
        let days = RecentlyDeleted.daysLeft(deletedOn: deletedDate, now: now(), calendar: calendar)
        // A setup past its last day but not yet removed (the purge runs at launch) still reads "0 days left".
        return RecentlyDeleted.daysLeftText(max(0, days))
    }

    func recover(_ setup: Setup) {
        storageController.recover(setup)
        load()
        lastRecovered = setup
    }

    func dismissRecovered() {
        lastRecovered = nil
    }
}
