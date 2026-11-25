//
//  ReviewEditSessionTests.swift
//  Skema Tests
//
//  View mode → pencil → edit mode → ✓ / Discard (Sketch R04, R04m, R04mx).
//

import Foundation
import Testing
@testable import Skema_Photo

@MainActor
@Suite("Review diagram: view and edit mode")
struct ReviewEditSessionTests {
    let storage = StorageController(inMemory: true)

    func makeViewModel() -> ReviewViewModel {
        let setup = Setup(setupName: "Studio A")
        setup.nodes.append(Equipment(category: .light, label: "L1", name: "Profoto D2", role: "Key"))
        storage.addSetup(setup)
        return ReviewViewModel(setup: setup, storageController: storage)
    }

    func makeUndoManager() -> UndoManager {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        return undoManager
    }

    /// One user action, closed as its own undo step.
    func addLight(_ name: String, to viewModel: ReviewViewModel, undoManager: UndoManager) {
        undoManager.beginUndoGrouping()
        viewModel.addEquipment(Equipment(category: .light, label: "L9", name: name), undoManager: undoManager)
        undoManager.endUndoGrouping()
        viewModel.updateUndoState(undoManager: undoManager)
    }

    @Test("Starts in view mode with nothing pending")
    func startsInViewMode() {
        let viewModel = makeViewModel()

        #expect(viewModel.isEditingDiagram == false)
        #expect(viewModel.hasPendingEdits == false)
    }

    @Test("Edit mode starts from a clean baseline, so earlier sheet edits are not undone by Discard")
    func beginEditingClearsUndo() {
        let viewModel = makeViewModel()
        let undoManager = makeUndoManager()
        addLight("Before edit mode", to: viewModel, undoManager: undoManager)

        viewModel.beginEditing(undoManager: undoManager)

        #expect(viewModel.isEditingDiagram)
        #expect(viewModel.hasPendingEdits == false)
        #expect(undoManager.canUndo == false)
    }

    @Test("A change in edit mode is pending until confirmed")
    func changeIsPending() {
        let viewModel = makeViewModel()
        let undoManager = makeUndoManager()
        viewModel.beginEditing(undoManager: undoManager)

        addLight("Rim", to: viewModel, undoManager: undoManager)

        #expect(viewModel.hasPendingEdits)
    }

    @Test("✓ keeps the changes, clears undo and returns to view mode")
    func confirmKeepsChanges() {
        let viewModel = makeViewModel()
        let undoManager = makeUndoManager()
        viewModel.beginEditing(undoManager: undoManager)
        addLight("Rim", to: viewModel, undoManager: undoManager)

        viewModel.confirmEdits(undoManager: undoManager)

        #expect(viewModel.isEditingDiagram == false)
        #expect(viewModel.hasPendingEdits == false)
        #expect(viewModel.nodes.count == 2)
        #expect(viewModel.draftSetup.nodes.count == 2)
    }

    @Test("Discard rolls every edit-mode change back and returns to view mode")
    func discardRollsBack() {
        let viewModel = makeViewModel()
        let undoManager = makeUndoManager()
        addLight("Before edit mode", to: viewModel, undoManager: undoManager)
        viewModel.beginEditing(undoManager: undoManager)
        addLight("Rim", to: viewModel, undoManager: undoManager)
        addLight("Hair", to: viewModel, undoManager: undoManager)

        viewModel.discardEdits(undoManager: undoManager)

        #expect(viewModel.isEditingDiagram == false)
        #expect(viewModel.hasPendingEdits == false)
        #expect(viewModel.nodes.map(\.name) == ["Profoto D2", "Before edit mode"])
    }

    @Test("Chips follow the team's display order: lights, accessories, cameras, each by label (A10-96)")
    func chipOrder() {
        let setup = Setup(setupName: "Studio A")
        setup.nodes.append(contentsOf: [
            Equipment(category: .accessory, label: "B1", name: "Bounce"),
            Equipment(category: .camera, label: "C2", name: "Side"),
            Equipment(category: .light, label: "L10", name: "Hair"),
            Equipment(category: .camera, label: "C1", name: "Main"),
            Equipment(category: .light, label: "L2", name: "Fill"),
            Equipment(category: .light, label: "L1", name: "Key")
        ])
        storage.addSetup(setup)
        let viewModel = ReviewViewModel(setup: setup, storageController: storage)

        #expect(viewModel.chipOrder.map(\.label) == ["L1", "L2", "L10", "B1", "C1", "C2"])
    }
}
