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
        let descriptor = FetchDescriptor<Setup>(sortBy: [SortDescriptor(\.setupName)])
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
