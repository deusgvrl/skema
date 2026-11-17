import Foundation
import Observation

/// State and actions for RecentlyDeletedView (Sketch R17).
/// Deleted setups stay recoverable for `retentionDays`, then `fetch()` purges them.
@MainActor
@Observable
final class RecentlyDeletedViewModel {
    static let retentionDays = 30

    var deletedSetups: [Setup] = []

    @ObservationIgnored private let storageController: StorageController

    init(storageController: StorageController? = nil) {
        self.storageController = storageController ?? StorageController.shared
    }

    func fetch() {
        storageController.purgeExpiredDeletions(retentionDays: Self.retentionDays)
        deletedSetups = storageController.fetchDeletedSetups()
    }

    func restore(_ setup: Setup) {
        storageController.restoreSetup(setup)
        fetch()
    }

    func daysLeft(for setup: Setup, now: Date = Date()) -> Int {
        guard let deletedAt = setup.deletedAt else { return Self.retentionDays }
        let daysElapsed = Int(now.timeIntervalSince(deletedAt) / 86_400)
        return max(0, Self.retentionDays - daysElapsed)
    }
}
