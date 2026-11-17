import SwiftData
import SwiftUI
import Foundation

/// The only place that talks to SwiftData. ViewModels read and write through this.
@MainActor
final class StorageController {
    static let shared = StorageController()
    
    let container: ModelContainer
    let context: ModelContext
    
    init(inMemory: Bool = false) {
        do {
            let schema = Schema([Setup.self, Equipment.self, ReferenceImage.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
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
    
    func deleteSetup(_ setup: Setup) {
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
        
    func save() {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Failed to save context: \(error.localizedDescription)")
            }
        }
    }
}
