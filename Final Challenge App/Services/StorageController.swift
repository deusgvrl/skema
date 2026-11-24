import SwiftData
import SwiftUI
import Foundation

/// The only place that talks to SwiftData. ViewModels read and write through this.
@MainActor
final class StorageController {
    static let shared = StorageController()

    let container: ModelContainer
    let context: ModelContext

    /// `url` stores the data in that file instead of the default one (tests that need a store on disk).
    init(inMemory: Bool = false, url: URL? = nil) {
        do {
            let schema = Schema([Setup.self, Equipment.self, ReferenceImage.self])
            let config = url.map { ModelConfiguration(schema: schema, url: $0) }
                ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
            self.container = try ModelContainer(for: schema, configurations: [config])
            self.context = container.mainContext
        } catch {
            fatalError("Failed to initialize SwiftData ModelContainer: \(error.localizedDescription)")
        }
    }

    func fetchAllSetups() -> [Setup] {
        // Setups in Recently Deleted are hidden everywhere else.
        let descriptor = FetchDescriptor<Setup>(
            predicate: #Predicate { $0.deletedDate == nil },
            sortBy: [SortDescriptor(\.setupName)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            print("Failed to fetch setups: \(error)")
            return []
        }
    }

    func addSetup(_ setup: Setup) {
        context.insert(setup)
        save()
    }

    /// Deletes a setup for good, with its equipment and photos. They are taken off the setup first, so a view
    /// still holding it reads none of them (reading a deleted item's fields stops the app).
    func deleteSetup(_ setup: Setup) {
        let nodes = setup.nodes
        let images = setup.referenceImages
        setup.nodes = []
        setup.referenceImages = []
        nodes.forEach(context.delete)
        images.forEach(context.delete)
        context.delete(setup)
        save()
    }

    /// Hides a setup in Recently Deleted. Its data stays until `purgeExpiredSetups` removes it.
    func moveToRecentlyDeleted(_ setup: Setup, at date: Date) {
        setup.deletedDate = date
        save()
    }

    func recover(_ setup: Setup) {
        setup.deletedDate = nil
        save()
    }

    func fetchRecentlyDeleted() -> [Setup] {
        let descriptor = FetchDescriptor<Setup>(predicate: #Predicate { $0.deletedDate != nil })
        do {
            return try context.fetch(descriptor)
        } catch {
            print("Failed to fetch recently deleted setups: \(error)")
            return []
        }
    }

    /// Removes for good every setup past its last day. The delete rules also remove its equipment and photos.
    func purgeExpiredSetups(now: Date, calendar: Calendar = .current) {
        for setup in fetchRecentlyDeleted() {
            guard let deletedDate = setup.deletedDate,
                  RecentlyDeleted.isExpired(deletedOn: deletedDate, now: now, calendar: calendar) else { continue }
            context.delete(setup)
        }
        save()
    }

    func addEquipment(_ equipment: Equipment, to setup: Setup) {
        setup.nodes.append(equipment)
        save()
    }

    func deleteEquipment(_ equipment: Equipment) {
        context.delete(equipment)
        save()
    }

    func updateEquipment(_ equipment: Equipment) {
        save()
    }

    func addReferenceImage(_ image: ReferenceImage, to setup: Setup) {
        setup.referenceImages.append(image)
        save()
    }

    func deleteReferenceImage(_ image: ReferenceImage) {
        context.delete(image)
        save()
    }

    /// Saves when there are changes and tells the caller if it fails.
    func trySave() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    func save() {
        do {
            try trySave()
        } catch {
            print("Failed to save context: \(error.localizedDescription)")
        }
    }
}
