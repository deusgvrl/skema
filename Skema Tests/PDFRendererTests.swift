import Testing
import PDFKit
import UIKit
@testable import Skema_Photo
import Foundation

@Suite("A4 PDF (A10-98)")
@MainActor
struct PDFRendererTests {

    /// Fixed dates in Jakarta time so the tests do not depend on the machine's time zone.
    private nonisolated static let jakarta: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return calendar
    }()

    private nonisolated static func jakartaDate(day: Int, month: Int = 11, year: Int = 2026) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: 10)
        return jakarta.date(from: parts)!
    }

    private let nov2 = PDFRendererTests.jakartaDate(day: 2)
    private let nov3 = PDFRendererTests.jakartaDate(day: 3)

    private func makeRenderer() -> PDFRenderer {
        PDFRenderer(calendar: Self.jakarta)
    }

    /// The base setup from the approved cases: 2 lights, 1 accessory, 1 camera, added in a mixed order.
    private func baseSetup(
        client: String = "Acme",
        notes: String = "Key light at 45°",
        firstSavedDate: Date? = PDFRendererTests.jakartaDate(day: 2),
        photoCount: Int = 0
    ) -> Setup {
        let setup = Setup(setupName: "Shoe shoot", client: client, project: "Spring", notes: notes)
        setup.firstSavedDate = firstSavedDate
        setup.nodes = [
            Equipment(category: .camera, label: "C1", name: "Camera body", lens: "50mm"),
            Equipment(category: .accessory, label: "A1", name: "Softbox"),
            Equipment(category: .light, label: "L2", name: "Fill light"),
            Equipment(category: .light, label: "L1", name: "Key light")
        ]
        setup.referenceImages = (0..<photoCount).map { index in
            photo(createdAt: Self.jakartaDate(day: 1 + index % 28, month: 10))
        }
        return setup
    }

    /// A tiny PNG, enough to be drawn as a photo.
    private func photo(createdAt: Date) -> ReferenceImage {
        let size = CGSize(width: 2, height: 2)
        let data = UIGraphicsImageRenderer(size: size).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return ReferenceImage(imageData: data, createdAt: createdAt)
    }

    private func document(_ setup: Setup, diagram: UIImage? = nil) throws -> PDFDocument {
        let data = makeRenderer().makePDF(for: setup, diagram: diagram)
        return try #require(PDFDocument(data: data), "The result should be readable as a PDF.")
    }

    private func text(of document: PDFDocument, page index: Int) -> String {
        document.page(at: index)?.string ?? ""
    }

    @Test("Case 1: the base setup makes 2 A4 pages")
    func twoA4Pages() throws {
        // Arrange
        let setup = baseSetup()

        // Act
        let pdf = try document(setup)

        // Assert
        #expect(pdf.pageCount == 2, "The base setup should make 2 pages.")
        for index in 0..<pdf.pageCount {
            let box = pdf.page(at: index)?.bounds(for: .mediaBox)
            #expect(box?.width == 595 && box?.height == 842, "Page \(index + 1) should be A4 (595 x 842 pt).")
        }
    }

    @Test("Case 2: page 1 shows title, subtitle, saved date, notes and page number")
    func pageOneContent() throws {
        // Arrange
        let setup = baseSetup()

        // Act
        let page1 = text(of: try document(setup), page: 0)

        // Assert
        for expected in ["Shoe shoot", "Acme · Spring", "Saved 2 Nov 2026", "Key light at 45°", "Page 1 of 2"] {
            #expect(page1.contains(expected), "Page 1 should contain \"\(expected)\".")
        }
    }

    @Test("Case 3: page 2 lists the equipment in display order and no subject or backdrop")
    func equipmentPage() throws {
        // Arrange
        let setup = baseSetup()

        // Act
        let page2 = text(of: try document(setup), page: 1)

        // Assert
        for expected in ["Equipment Details", "2 lights · 1 accessory · 1 camera", "Skema Photo"] {
            #expect(page2.contains(expected), "Page 2 should contain \"\(expected)\".")
        }
        let positions = ["L1", "L2", "A1", "C1"].map { page2.range(of: $0)?.lowerBound }
        #expect(!positions.contains(nil), "All four labels should be on page 2.")
        let offsets = positions.compactMap { $0.map { page2.distance(from: page2.startIndex, to: $0) } }
        #expect(offsets == offsets.sorted(), "The labels should appear in the order L1, L2, A1, C1.")
        #expect(!page2.contains("Subject"), "There is no subject row.")
        #expect(!page2.contains("Backdrop"), "There is no backdrop row.")
    }

    @Test("Case 4: photos show the heading and are numbered in order")
    func referencesNumbered() throws {
        // Arrange
        let setup = baseSetup()
        setup.referenceImages = [photo(createdAt: nov3), photo(createdAt: nov2)]

        // Act
        let page2 = text(of: try document(setup), page: 1)

        // Assert
        #expect(page2.contains("References · 2 photos"), "Page 2 should have the references heading.")
        let first = page2.range(of: "Reference 1")
        let second = page2.range(of: "Reference 2")
        #expect(first != nil && second != nil, "Both photo labels should be on page 2.")
        if let first, let second {
            #expect(first.lowerBound < second.lowerBound, "Reference 1 should come before Reference 2.")
        }
    }

    @Test("Case 5: no photos means no References section")
    func noReferencesWithoutPhotos() throws {
        // Arrange
        let setup = baseSetup()

        // Act
        let pdf = try document(setup)

        // Assert
        for index in 0..<pdf.pageCount {
            let pageText = text(of: pdf, page: index)
            #expect(!pageText.contains("References"), "Page \(index + 1) should not mention References.")
        }
    }

    @Test("Case 6: 6 photos make 3 pages, 4 photos per page")
    func sixPhotosThreePages() throws {
        // Arrange
        let setup = baseSetup(photoCount: 6)

        // Act
        let pdf = try document(setup)

        // Assert
        #expect(pdf.pageCount == 3, "6 photos should make 3 pages.")
        let page2 = text(of: pdf, page: 1)
        let page3 = text(of: pdf, page: 2)
        #expect(page3.contains("Reference 5") && page3.contains("Reference 6"), "Page 3 should have photos 5 and 6.")
        #expect(page2.contains("Reference 4"), "Page 2 should have photo 4.")
        #expect(!page2.contains("Reference 5"), "Page 2 should not have photo 5.")
    }

    @Test("Case 7: long notes continue on the next page and equipment starts after them")
    func longNotesContinue() throws {
        // Arrange
        let longNotes = String(repeating: "Move the key light a little closer. ", count: 100)
        let setup = baseSetup(notes: longNotes)

        // Act
        let pdf = try document(setup)

        // Assert
        #expect(pdf.pageCount == 3, "Long notes should add one page.")
        let page2 = text(of: pdf, page: 1)
        #expect(page2.contains("Notes (continued)"), "Page 2 should continue the notes.")
        #expect(!page2.contains("Equipment Details"), "Equipment must start on a new page after the notes.")
        #expect(text(of: pdf, page: 2).contains("Equipment Details"), "Page 3 should have the equipment.")
    }

    @Test("Case 8: many lights run over to a second table page and no text is under 9 pt")
    func tableSpansPagesAtNineOrMore() throws {
        // Arrange
        let setup = baseSetup()
        setup.nodes = (1...60).map { Equipment(category: .light, label: "L\($0)", name: "Light \($0)", role: "Key") }

        // Act
        let pdf = try document(setup)

        // Assert
        let pages = (0..<pdf.pageCount).map { text(of: pdf, page: $0) }
        let firstPage = pages.firstIndex { $0.contains("L1") && $0.contains("Equipment Details") }
        let lastPage = pages.firstIndex { $0.contains("L60") }
        #expect(firstPage != nil && lastPage != nil, "Both the first and the last label should be found.")
        if let firstPage, let lastPage {
            #expect(lastPage > firstPage, "The last row should be on a later page than the first.")
        }
        var sizes: [CGFloat] = []
        for index in 0..<pdf.pageCount {
            guard let attributed = pdf.page(at: index)?.attributedString else { continue }
            attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
                if let font = value as? UIFont { sizes.append(font.pointSize) }
            }
        }
        #expect(!sizes.isEmpty, "The check should have found font sizes to look at.")
        #expect(sizes.allSatisfy { $0 >= 9 }, "Smallest size found: \(sizes.min() ?? 0) pt; it should be 9 pt or more.")
    }

    @Test("Case 9: an empty client leaves no stray separator")
    func emptyClientNoSeparator() throws {
        // Arrange
        let setup = baseSetup(client: "")

        // Act
        let page1 = text(of: try document(setup), page: 0)

        // Assert
        #expect(page1.contains("Spring"), "The project should still show.")
        #expect(!page1.contains(" · Spring"), "There should be no separator before the project.")
        #expect(!page1.contains("Spring · "), "There should be no separator after the project.")
    }

    @Test("Case 10: every page says its own number out of the total")
    func pageNumbers() throws {
        // Arrange
        let setup = baseSetup(photoCount: 6)

        // Act
        let pdf = try document(setup)

        // Assert
        #expect(pdf.pageCount == 3, "This data should make 3 pages.")
        for index in 0..<pdf.pageCount {
            let expected = "Page \(index + 1) of 3"
            #expect(text(of: pdf, page: index).contains(expected), "Page \(index + 1) should say \"\(expected)\".")
        }
    }

    @Test("Case 11: no first saved date means no Saved line")
    func noSavedLineWithoutDate() throws {
        // Arrange
        let setup = baseSetup(firstSavedDate: nil)

        // Act
        let page1 = text(of: try document(setup), page: 0)

        // Assert
        #expect(!page1.contains("Saved"), "Page 1 should not have a Saved line.")
    }
}
