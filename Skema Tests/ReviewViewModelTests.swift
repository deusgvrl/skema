//
//  ReviewViewModelTests.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 12/11/26.
//

import Testing
import Foundation
import SwiftUI
@testable import Final_Challenge_App 


@Suite("ReviewViewModel Tests")
@MainActor
struct ReviewViewModelTests {

    @Test("Initialization with existing setup loads nodes correctly")
    func testInitWithExistingSetup() {
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Studio A", client: "Acme", project: "Commercial")
        let light = Equipment(category: .light, label: "E1", name: "Key Light", role: "Main")
        
        setup.nodes.append(light)
        storage.addSetup(setup)

        let viewModel = ReviewViewModel(setup: setup)

        #expect(viewModel.draftSetup.setupName == "Studio A")
        #expect(viewModel.nodes.count == 1)
        #expect(viewModel.nodes.first?.name == "Key Light")
    }

    @Test("Initialization without setup creates default draft setup in test container")
    func testInitWithNilSetup() {
        let storage = StorageController(inMemory: true)
        let viewModel = ReviewViewModel(setup: nil, storageController: storage)

        #expect(viewModel.draftSetup.setupName == "New Setup")
        #expect(storage.fetchAllSetups().count == 1)
    }

    @Test("addEquipment appends node and registers in SwiftData")
    func testAddEquipment() {
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Test Setup")
        storage.addSetup(setup)

        let viewModel = ReviewViewModel(setup: setup, storageController: storage)
        let newCamera = Equipment(category: .camera, label: "E1", name: "Sony A7S III", role: "Main Cam")

        let undoManager = UndoManager()
        viewModel.addEquipment(newCamera, undoManager: undoManager)

        #expect(viewModel.nodes.count == 1)
        #expect(viewModel.nodes.first?.name == "Sony A7S III")
        #expect(viewModel.draftSetup.nodes.count == 1)
    }

    @Test("discardSetup removes draft setup from storage")
    func testDiscardSetup() {
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Temporary Setup")
        storage.addSetup(setup)

        let viewModel = ReviewViewModel(setup: setup, storageController: storage)
        #expect(storage.fetchAllSetups().count == 1)

        viewModel.discardSetup()

        #expect(storage.fetchAllSetups().isEmpty)
    }

    @Test("Undo and redo state updates correctly")
    func testUndoRedoState() {
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Undo Test")
        storage.addSetup(setup)

        let viewModel = ReviewViewModel(setup: setup)
        let undoManager = UndoManager()

        let item = Equipment(category: .light, label: "E1", name: "Rim Light", role: "Back")
        viewModel.addEquipment(item, undoManager: undoManager)

        #expect(viewModel.nodes.count == 1)
        #expect(viewModel.canUndo == true)

        undoManager.undo()
        viewModel.updateUndoState(undoManager: undoManager)

        #expect(viewModel.nodes.isEmpty)
        #expect(viewModel.canRedo == true)
    }
}
