//
//  StorageControllerTests.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 10/11/26.
//

import Testing
import SwiftData
@testable import Final_Challenge_App
import Foundation

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
    
    @Test("Draft Flow: Create Equipment First, Then Setup, Then Save")
    func draftFlowSavesSetupAndEquipment() {
        let keyLight = Equipment(category: .light, name: "Key Light", power: "100%")
        let mainCamera = Equipment(category: .camera, name: "Main Camera", lens: "50mm")
        
        let draftSetup = Setup(setupName: "Commercial Portrait", client: "Acme Corp")
        
        draftSetup.nodes.append(keyLight)
        draftSetup.nodes.append(mainCamera)
        
        #expect(storageController.fetchAllSetups().isEmpty, "Database should be empty before saving.")
        
        storageController.addSetup(draftSetup)
        
        let fetchedSetups = storageController.fetchAllSetups()
        let savedSetup = fetchedSetups.first
        
        #expect(fetchedSetups.count == 1, "Should save exactly one setup.")
        #expect(savedSetup?.setupName == "Commercial Portrait", "Setup name should match.")
        #expect(savedSetup?.client == "Acme Corp", "Client name should match.")
        
        // Verify that SwiftData automatically saved the associated equipment
        let savedNodes = savedSetup?.nodes ?? []
        #expect(savedNodes.count == 2, "The setup should contain the 2 equipment nodes we added.")
        
        let nodeNames = savedNodes.map { $0.name }
        #expect(nodeNames.contains("Key Light"))
        #expect(nodeNames.contains("Main Camera"))
    }
    
    @Test("Upload and Delete Reference Image")
    func uploadAndDeleteReferenceImage() throws {
        let setup = Setup(setupName: "Product Shoot")
        storageController.addSetup(setup)
        
        let dummyImageData = Data("simulated_jpeg_data".utf8)
        let referenceImage = ReferenceImage(imageData: dummyImageData)
        
        storageController.addReferenceImage(referenceImage, to: setup)
        
        let fetchedSetups = storageController.fetchAllSetups()
        let savedSetup = fetchedSetups.first
        
        #expect(savedSetup?.referenceImages.count == 1, "Setup should have exactly 1 reference image.")
        #expect(savedSetup?.referenceImages.first?.imageData == dummyImageData, "The saved image data should match the uploaded data.")
        
        // Make sure to get the exact image object from the database context
        guard let imageToDelete = savedSetup?.referenceImages.first else {
            Issue.record("Failed to find the image to delete.")
            return
        }
        
        storageController.deleteReferenceImage(imageToDelete)
        
        let setupsAfterDelete = storageController.fetchAllSetups()
        #expect(setupsAfterDelete.first?.referenceImages.isEmpty == true, "The reference image array should be empty after deletion.")
        
        // Verify the image is completely gone from the SwiftData context entirely
        let imageDescriptor = FetchDescriptor<ReferenceImage>()
        let remainingImagesInDB = try storageController.context.fetch(imageDescriptor)
        #expect(remainingImagesInDB.isEmpty, "The image should be completely removed from the database.")
    }
}
