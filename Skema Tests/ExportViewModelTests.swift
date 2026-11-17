//
//  ExportViewModelTests.swift
//  Skema Tests
//
//  ••• → Share (Sketch R14 → R15, R15f "Couldn't Create PDF").
//

import Foundation
import PDFKit
import Testing
@testable import Final_Challenge_App

@MainActor
@Suite("Share as PDF")
struct ExportViewModelTests {
    struct BuildError: Error {}

    @Test("Share builds the file and hands it to the share sheet")
    func shareSucceeds() {
        let file = URL(fileURLWithPath: "/tmp/Candle.pdf")
        let viewModel = ExportViewModel(setup: Setup(setupName: "Candle"), makeFile: { _ in file })

        viewModel.share()

        #expect(viewModel.sharedPDF?.url == file)
        #expect(viewModel.showsFailure == false)
    }

    @Test("A failed build shows Couldn't Create PDF, and Try Again can succeed")
    func failureThenRetry() {
        var fails = true
        let file = URL(fileURLWithPath: "/tmp/Candle.pdf")
        let viewModel = ExportViewModel(setup: Setup(setupName: "Candle"), makeFile: { _ in
            if fails { throw BuildError() }
            return file
        })

        viewModel.share()
        #expect(viewModel.sharedPDF == nil)
        #expect(viewModel.showsFailure)

        fails = false
        viewModel.share()
        #expect(viewModel.sharedPDF?.url == file)
        #expect(viewModel.showsFailure == false)
    }

    @Test("The real build writes a two-page PDF with the diagram drawn")
    func realBuild() throws {
        let storage = StorageController(inMemory: true)
        let setup = Setup(setupName: "Skincare / soft daylight", client: "Aesop")
        setup.nodes.append(Equipment(category: .light, label: "L1", name: "Profoto D2", role: "Key",
                                     position: CGPoint(x: -120, y: -80), distance: "1.35"))
        storage.addSetup(setup)

        let url = try ExportViewModel.makePDFFile(for: setup)

        #expect(url.lastPathComponent == "Skincare - soft daylight.pdf")
        let pdf = try #require(PDFDocument(url: url))
        #expect(pdf.pageCount == 2)
        let diagram = try #require(ExportViewModel.diagramImage(for: setup))
        #expect(diagram.size.width > 0)
    }
}
