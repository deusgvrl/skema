//
//  ProjectDetailsViewModelTests.swift
//  Skema Tests
//
//  Project Details (Sketch R07, R07e name missing, R07f save failed).
//

import Foundation
import Testing
@testable import Final_Challenge_App

@MainActor
@Suite("Project Details")
struct ProjectDetailsViewModelTests {
    struct SaveError: Error {}

    func makeSetup() -> Setup {
        Setup(setupName: "Untitled Setup", client: "Aesop", project: "November catalog", notes: "Flag the key")
    }

    @Test("Starts from the setup's values with no error showing")
    func startsFromSetup() {
        let viewModel = ProjectDetailsViewModel(setup: makeSetup(), saveChanges: {})

        #expect(viewModel.name == "Untitled Setup")
        #expect(viewModel.client == "Aesop")
        #expect(viewModel.project == "November catalog")
        #expect(viewModel.notes == "Flag the key")
        #expect(viewModel.canSave)
        #expect(viewModel.showsNameError == false)
    }

    @Test("A setup that arrives without a name can't be saved, but shows no error until edited")
    func blankOnArrival() {
        let viewModel = ProjectDetailsViewModel(setup: Setup(setupName: ""), saveChanges: {})

        #expect(viewModel.canSave == false)
        #expect(viewModel.showsNameError == false)
    }

    @Test("Clearing the name to spaces shows the error and disables ✓", arguments: ["", "   "])
    func clearedName(name: String) {
        let viewModel = ProjectDetailsViewModel(setup: makeSetup(), saveChanges: {})

        viewModel.name = name

        #expect(viewModel.canSave == false)
        #expect(viewModel.showsNameError)
    }

    @Test("Typing doesn't change the setup until ✓, so Cancel leaves it untouched")
    func editsStayLocal() {
        let setup = makeSetup()
        let viewModel = ProjectDetailsViewModel(setup: setup, saveChanges: {})

        viewModel.name = "Perfume / low key"
        viewModel.client = "Maison Noir"

        #expect(setup.setupName == "Untitled Setup")
        #expect(setup.client == "Aesop")
    }

    @Test("✓ writes trimmed values and saves")
    func saveWrites() {
        let setup = makeSetup()
        var saveCount = 0
        let viewModel = ProjectDetailsViewModel(setup: setup, saveChanges: { saveCount += 1 })
        viewModel.name = "  Perfume / low key "
        viewModel.client = " Maison Noir"
        viewModel.project = "Holiday "
        viewModel.notes = "Mark tripod feet"

        let saved = viewModel.save()

        #expect(saved)
        #expect(saveCount == 1)
        #expect(setup.setupName == "Perfume / low key")
        #expect(setup.client == "Maison Noir")
        #expect(setup.project == "Holiday")
        #expect(setup.notes == "Mark tripod feet")
        #expect(viewModel.saveFailure == nil)
    }

    @Test("A failed save keeps the details and explains a full iPhone with Sketch's copy")
    func outOfSpace() {
        let full = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        let wrapped = NSError(domain: "SwiftData", code: 1, userInfo: [NSUnderlyingErrorKey: full])
        let viewModel = ProjectDetailsViewModel(setup: makeSetup(), saveChanges: { throw wrapped })
        viewModel.name = "Perfume / low key"

        let saved = viewModel.save()

        #expect(saved == false)
        #expect(viewModel.saveFailure == ProjectDetailsViewModel.storageFullMessage)
        #expect(viewModel.name == "Perfume / low key")
    }

    @Test("Any other failure gets the general message, and Try Again can succeed")
    func otherFailureThenRetry() {
        var shouldFail = true
        let viewModel = ProjectDetailsViewModel(setup: makeSetup(), saveChanges: {
            if shouldFail { throw SaveError() }
        })

        #expect(viewModel.save() == false)
        #expect(viewModel.saveFailure == ProjectDetailsViewModel.generalFailureMessage)

        shouldFail = false
        #expect(viewModel.save())
        #expect(viewModel.saveFailure == nil)
    }

    @Test("Going back to the diagram keeps what was typed on the setup, without saving")
    func applyWithoutSaving() {
        let setup = makeSetup()
        var saveCount = 0
        let viewModel = ProjectDetailsViewModel(setup: setup, saveChanges: { saveCount += 1 })
        viewModel.name = "Perfume / low key"

        viewModel.applyWithoutSaving()

        #expect(setup.setupName == "Perfume / low key")
        #expect(saveCount == 0)
    }
}
