//
//  PDFRendererTests.swift
//  Skema Tests
//
//  The A4 PDF itself (Sketch R15q / R15q·2), read back with PDFKit.
//

import Foundation
import PDFKit
import Testing
import UIKit
@testable import Final_Challenge_App

@MainActor
@Suite("PDF renderer")
struct PDFRendererTests {
    func makeSetup(notes: String = "Flag the key light.", photos: Int = 2) -> Setup {
        let setup = Setup(setupName: "Skincare / soft daylight", client: "Aesop", project: "November catalog", notes: notes)
        setup.nodes.append(contentsOf: [
            Equipment(category: .light, label: "L1", name: "Profoto D2 500", role: "Key light", power: "7.0",
                      colorTemp: "5600", distance: "1.35"),
            Equipment(category: .camera, label: "C1", name: "Fujifilm GFX 50R", role: "Main camera", distance: "1.75")
        ])
        for index in 0..<photos {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
            }
            setup.referenceImages.append(ReferenceImage(imageData: image.jpegData(compressionQuality: 0.8)!,
                                                        createdAt: Date(timeIntervalSince1970: Double(index))))
        }
        return setup
    }

    func document(for setup: Setup, diagram: UIImage? = nil) throws -> PDFDocument {
        let data = PDFRenderer().render(SetupPDFContent(setup: setup), diagram: diagram)
        return try #require(PDFDocument(data: data))
    }

    @Test("Two A4 pages for a normal setup")
    func twoA4Pages() throws {
        let pdf = try document(for: makeSetup())

        #expect(pdf.pageCount == 2)
        let bounds = try #require(pdf.page(at: 0)).bounds(for: .mediaBox)
        #expect(bounds.size == CGSize(width: 595, height: 842))
    }

    @Test("Page 1: name, client · project, diagram, notes, footer")
    func pageOne() throws {
        let text = try #require(try document(for: makeSetup()).page(at: 0)?.string)

        #expect(text.contains("Skincare / soft daylight"))
        #expect(text.contains("Aesop · November catalog"))
        #expect(text.contains("LIGHTING DIAGRAM"))
        #expect(text.contains("NOTES"))
        #expect(text.contains("Flag the key light."))
        #expect(text.contains("Page 1 of 2"))
    }

    @Test("No Notes section when there are no notes")
    func noNotes() throws {
        let text = try #require(try document(for: makeSetup(notes: "  ")).page(at: 0)?.string)

        #expect(!text.contains("NOTES"))
    }

    @Test("Page 2: equipment table and references")
    func pageTwo() throws {
        let text = try #require(try document(for: makeSetup()).page(at: 1)?.string)

        #expect(text.contains("Equipment Details"))
        #expect(text.contains("1 light · 1 camera"))
        #expect(text.contains("Profoto D2 500"))
        #expect(text.contains("1.35 m"))
        #expect(text.contains("7.0 · 5600 K"))
        #expect(text.contains("REFERENCES · 2 PHOTOS"))
        #expect(text.contains("Reference 2"))
        #expect(text.contains("Page 2 of 2"))
    }

    @Test("Many items add pages, and every footer counts the real total")
    func overflow() throws {
        let setup = makeSetup(photos: 9)
        for index in 2...30 {
            setup.nodes.append(Equipment(category: .light, label: "L\(index)", name: "Light \(index)"))
        }
        let pdf = try document(for: setup)

        #expect(pdf.pageCount > 2)
        let lastText = try #require(pdf.page(at: pdf.pageCount - 1)?.string)
        #expect(lastText.contains("Page \(pdf.pageCount) of \(pdf.pageCount)"))
    }

    @Test("A broken photo doesn't stop the PDF")
    func brokenPhoto() throws {
        let setup = makeSetup(photos: 0)
        setup.referenceImages.append(ReferenceImage(imageData: Data([0, 1, 2])))

        let pdf = try document(for: setup)

        #expect(pdf.pageCount == 2)
    }

    @Test("The file is written under its setup's name")
    func writesFile() throws {
        let content = SetupPDFContent(setup: makeSetup())
        let data = PDFRenderer().render(content, diagram: nil)

        let url = try PDFRenderer().writeFile(data, named: content.fileName)

        #expect(url.lastPathComponent == "Skincare - soft daylight.pdf")
        #expect(try Data(contentsOf: url) == data)
    }
}
