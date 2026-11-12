//
//  EquipmentFormViewModel.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 12/11/26.
//

import Testing
import Foundation
import SwiftUI
@testable import Final_Challenge_App 

@Suite("EquipmentFormViewModel Tests")
@MainActor
struct EquipmentFormViewModelTests {

    @Test("isFormValid returns false for empty name and true when name is set")
    func testFormValidation() {
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Form Validation Test")
        storage.addSetup(setup)
        let reviewVM = ReviewViewModel(setup: setup)

        let formVM = EquipmentFormViewModel(editingNodeId: nil, reviewViewModel: reviewVM)

        #expect(formVM.isFormValid == false)

        formVM.name = "  "
        #expect(formVM.isFormValid == false)

        formVM.name = "Aputure 600d"
        #expect(formVM.isFormValid == true)
    }

    @Test("loadData populates form fields when editing existing node")
    func testLoadDataForEditing() {
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Edit Test")
        let existingNode = Equipment(
            category: .light,
            label: "E1",
            name: "Nanlite 300",
            role: "Key Light",
            power: "80%",
            colorTemp: "5600"
        )
        setup.nodes.append(existingNode)
        storage.addSetup(setup)

        let reviewVM = ReviewViewModel(setup: setup)
        let formVM = EquipmentFormViewModel(editingNodeId: existingNode.id, reviewViewModel: reviewVM)

        #expect(formVM.isEditing == true)
        #expect(formVM.name == "Nanlite 300")
        #expect(formVM.role == "Key Light")
        #expect(formVM.power == "80%")
        #expect(formVM.colorTemp == "5600")
    }

    @Test("saveNode creates new equipment when editingNodeId is nil")
    func testSaveNewNode() {
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Save New Node Test")
        storage.addSetup(setup)

        let reviewVM = ReviewViewModel(setup: setup)
        let formVM = EquipmentFormViewModel(editingNodeId: nil, reviewViewModel: reviewVM)

        formVM.category = .camera
        formVM.name = "Canon C70"
        formVM.role = "A-Cam"
        formVM.lens = "24-70mm f/2.8"

        var completionCalled = false
        formVM.saveNode(undoManager: nil) {
            completionCalled = true
        }

        #expect(completionCalled == true)
        #expect(reviewVM.nodes.count == 1)
        #expect(reviewVM.nodes.first?.name == "Canon C70")
        #expect(reviewVM.nodes.first?.lens == "24-70mm f/2.8")
    }

    @Test("saveNode updates existing node properties when editing")
    func testSaveExistingNode() {
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Update Node Test")
        let node = Equipment(category: .light, label: "E1", name: "Old Light Name", role: "Key")
        setup.nodes.append(node)
        storage.addSetup(setup)

        let reviewVM = ReviewViewModel(setup: setup)
        let formVM = EquipmentFormViewModel(editingNodeId: node.id, reviewViewModel: reviewVM)

        formVM.name = "Updated Light Name"
        formVM.power = "100%"

        formVM.saveNode(undoManager: nil) {}

        #expect(reviewVM.nodes.count == 1)
        #expect(reviewVM.nodes.first?.name == "Updated Light Name")
        #expect(reviewVM.nodes.first?.power == "100%")
    }

    @Test("deleteNode removes node from reviewViewModel")
    func testDeleteNode() {
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Delete Node Test")
        let node = Equipment(category: .accessory, label: "E1", name: "C-Stand", role: "")
        setup.nodes.append(node)
        storage.addSetup(setup)

        let reviewVM = ReviewViewModel(setup: setup)
        let formVM = EquipmentFormViewModel(editingNodeId: node.id, reviewViewModel: reviewVM)

        var completionCalled = false
        formVM.deleteNode(undoManager: nil) {
            completionCalled = true
        }

        #expect(completionCalled == true)
        #expect(reviewVM.nodes.isEmpty)
    }
}
