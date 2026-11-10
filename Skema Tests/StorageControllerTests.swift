//
//  StorageControllerTests.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 10/11/26.
//

import Testing
import SwiftData
@testable import Final_Challenge_App

@Suite("Storage Controller Tests")
@MainActor
struct StorageControllerTests {
    
    let storageController: StorageController
    
    init() {
        storageController = StorageController(inMemory: true)
    }
    
    @Test("Add Setup Saves To Database")
    func addSetupSavesToDatabase() {
        // Arrange
        let newSetup = Setup(setupName: "Test Portrait Setup", client: "Apple")
        
        // Act
        storageController.addSetup(newSetup)
        let fetchedSetups = storageController.fetchAllSetups()
        
        // Assert
        #expect(fetchedSetups.count == 1, "There should be exactly 1 setup in the database.")
        #expect(fetchedSetups.first?.setupName == "Test Portrait Setup")
        #expect(fetchedSetups.first?.client == "Apple")
    }
    
    @Test("Fetch Setup Retrieves Associated Equipment")
    func fetchSetupRetrievesAssociatedEquipment() {
        let setup = Setup(setupName: "Studio Interview")
        let camera = Equipment(category: .camera, name: "Main Camera")
        let keyLight = Equipment(category: .light, name: "Key Light")
        let fillLight = Equipment(category: .light, name: "Fill Light")
        
        storageController.addSetup(setup)
        storageController.addEquipment(camera, to: setup)
        storageController.addEquipment(keyLight, to: setup)
        storageController.addEquipment(fillLight, to: setup)
        
        let fetchedSetups = storageController.fetchAllSetups()
        let fetchedSetup = fetchedSetups.first
        
        #expect(fetchedSetups.count == 1, "Should fetch exactly one setup.")
        #expect(fetchedSetup != nil, "Fetched setup should not be nil.")
        #expect(fetchedSetup?.setupName == "Studio Interview")
        
        let fetchedNodes = fetchedSetup?.nodes ?? []
        #expect(fetchedNodes.count == 3, "Setup should contain exactly 3 equipment nodes.")
        
        let nodeNames = fetchedNodes.map { $0.name }
        #expect(nodeNames.contains("Main Camera"))
        #expect(nodeNames.contains("Key Light"))
        #expect(nodeNames.contains("Fill Light"))
    }
    
    @Test("Update Equipment Persists Changes")
    func updateEquipmentPersistsChanges() {
        let setup = Setup(setupName: "Product Shoot")
        let light = Equipment(category: .light, name: "Key Light", power: "5.0")
        
        storageController.addSetup(setup)
        storageController.addEquipment(light, to: setup)
        
        light.power = "8.5"
        light.name = "Main Key Light"
        storageController.updateEquipment(light)
        
        let fetchedSetups = storageController.fetchAllSetups()
        let fetchedLight = fetchedSetups.first?.nodes.first
        
        #expect(fetchedLight?.power == "8.5")
        #expect(fetchedLight?.name == "Main Key Light")
    }
    
    @Test("Cascade Deletion Removes Associated Equipment")
    func cascadeDeleteSetupDeletesAssociatedEquipment() throws {
        let setup = Setup(setupName: "Temporary Setup")
        let camera = Equipment(category: .camera, name: "Sony A7IV")
        let light = Equipment(category: .light, name: "Godox AD200")
        
        storageController.addSetup(setup)
        storageController.addEquipment(camera, to: setup)
        storageController.addEquipment(light, to: setup)
        
        #expect(storageController.fetchAllSetups().first?.nodes.count == 2)
        
        storageController.deleteSetup(setup)
        
        let fetchedSetups = storageController.fetchAllSetups()
        #expect(fetchedSetups.isEmpty, "The setup should be deleted.")
        
        let equipmentDescriptor = FetchDescriptor<Equipment>()
        let remainingEquipment = try storageController.context.fetch(equipmentDescriptor)
        
        #expect(remainingEquipment.isEmpty, "All associated equipment should have been deleted automatically via cascade.")
    }
}
