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

    /// A tiny PNG, enough to be drawn as a photo. Its colour follows the date, so no two photos are the same image.
    private func photo(createdAt: Date) -> ReferenceImage {
        let size = CGSize(width: 2, height: 2)
        let hue = CGFloat(Int(createdAt.timeIntervalSince1970 / 86_400) % 97) / 97
        let data = UIGraphicsImageRenderer(size: size).pngData { context in
            UIColor(hue: hue, saturation: 1, brightness: 1, alpha: 1).setFill()
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

    /// How many images a page draws, from its Resources → XObject dictionary.
    private func imageCount(of document: PDFDocument, page index: Int) -> Int {
        guard let dictionary = document.page(at: index)?.pageRef?.dictionary else { return 0 }
        var resources: CGPDFDictionaryRef?
        var objects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources,
              CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else { return 0 }
        var count = 0
        CGPDFDictionaryApplyBlock(objects, { _, object, _ in
            var stream: CGPDFStreamRef?
            var subtype: UnsafePointer<CChar>?
            if CGPDFObjectGetValue(object, .stream, &stream), let stream,
               let streamDictionary = CGPDFStreamGetDictionary(stream),
               CGPDFDictionaryGetName(streamDictionary, "Subtype", &subtype), let subtype,
               String(cString: subtype) == "Image" {
                count += 1
            }
            return true
        }, nil)
        return count
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

    @Test("Case 3: page 2 has the subject, cameras, lights and accessories tables, in that order")
    func equipmentPage() throws {
        // Arrange
        let setup = baseSetup()

        // Act
        let page2 = text(of: try document(setup), page: 1)

        // Assert
        for expected in ["Equipment Details", "1 camera · 2 lights · 1 accessory", "Skema Photo"] {
            #expect(page2.contains(expected), "Page 2 should contain \"\(expected)\".")
        }
        let inOrder = [
            "SUBJECT", "CAMERAS", "Camera body", "LIGHTS", "Key light", "Fill light", "ACCESSORIES", "Softbox"
        ]
        let positions = inOrder.compactMap { page2.range(of: $0)?.lowerBound }
        #expect(positions.count == inOrder.count, "Every table title and item should be on page 2.")
        #expect(positions == positions.sorted(), "The tables and their items should be in order.")
        #expect(!page2.contains("Backdrop"), "There is no backdrop row.")
    }

    @Test("Case 4: photos show the heading and no caption under each photo")
    func referencesWithoutCaptions() throws {
        // Arrange
        let setup = baseSetup()
        setup.referenceImages = [photo(createdAt: nov3), photo(createdAt: nov2)]

        // Act
        let pdf = try document(setup)

        // Assert
        let page2 = text(of: pdf, page: 1)
        #expect(page2.contains("References · 2 photos"), "Page 2 should have the references heading.")
        #expect(imageCount(of: pdf, page: 1) == 2, "Page 2 should draw both photos.")
        for index in 0..<pdf.pageCount {
            #expect(!text(of: pdf, page: index).contains("Reference 1"), "Page \(index + 1) has no photo captions.")
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

    @Test("Case 6: with no captions, 6 photos fit under the tables and photo 7 goes on the next page")
    func sevenPhotosThreePages() throws {
        // Arrange
        let setup = baseSetup(photoCount: 7)

        // Act
        let pdf = try document(setup)

        // Assert
        #expect(pdf.pageCount == 3, "Page 2 has the tables and photos 1 to 6; page 3 has photo 7.")
        #expect(imageCount(of: pdf, page: 1) == 6, "Page 2 should have photos 1 to 6.")
        #expect(imageCount(of: pdf, page: 2) == 1, "Page 3 should have photo 7.")
        #expect(!text(of: pdf, page: 1).contains("Reference 1"), "Photos have no captions.")
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
        #expect(page2.contains("NOTES (CONTINUED)"), "Page 2 should continue the notes.")
        #expect(!page2.contains("Equipment Details"), "Equipment must start on a new page after the notes.")
        #expect(text(of: pdf, page: 2).contains("Equipment Details"), "Page 3 should have the equipment.")
    }

    @Test("Case 8: many lights run over to a second table page and no text is under 9 pt")
    func tableSpansPagesAtNineOrMore() throws {
        // Arrange
        let setup = baseSetup()
        setup.nodes = (1...60).map { Equipment(category: .light, name: "Light \($0)", role: "Key") }

        // Act
        let pdf = try document(setup)

        // Assert
        let pages = (0..<pdf.pageCount).map { text(of: pdf, page: $0) }
        let firstPage = pages.firstIndex { $0.contains("Light 1") && $0.contains("Equipment Details") }
        let lastPage = pages.firstIndex { $0.contains("Light 60") }
        #expect(firstPage != nil && lastPage != nil, "Both the first and the last light should be found.")
        if let firstPage, let lastPage {
            #expect(lastPage > firstPage, "The last row should be on a later page than the first.")
            #expect(pages[lastPage].contains("LIGHTS (CONTINUED)"), "A later page should repeat the table title.")
            #expect(pages[lastPage].contains("Power"), "A later page should repeat the column titles.")
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
        // Arrange: 6 photos under the tables, 6 on page 3, 1 on page 4.
        let setup = baseSetup(photoCount: 13)

        // Act
        let pdf = try document(setup)

        // Assert
        #expect(pdf.pageCount == 4, "This data should make 4 pages.")
        for index in 0..<pdf.pageCount {
            let expected = "Page \(index + 1) of 4"
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

    @Test("Case 12: the notes box is a tenth of page 1")
    func notesBoxHeight() {
        #expect(abs(PDFLayout.notesBoxHeight - 84.2) < 0.01)
    }

    @Test("Case 14: a row of photos and its gaps is exactly as wide as the page content")
    func photoRowWidth() {
        let columns = CGFloat(PDFLayout.photoColumns)
        let row = columns * PDFLayout.photoColumnWidth + (columns - 1) * PDFLayout.spacing

        #expect(abs(row - PDFLayout.contentWidth) < 0.01)
    }

    @Test("Case 13: the footer says what heights and distances are measured from")
    func footer() throws {
        let page1 = text(of: try document(baseSetup()), page: 0)

        #expect(page1.contains("Heights are measured from the floor, distances to the subject."))
    }
}

@Suite("PDF equipment tables")
@MainActor
struct PDFEquipmentTablesTests {
    private func tables(_ nodes: [Equipment], subjectHeight: String = "") -> [PDFTable] {
        let setup = Setup(setupName: "Shoe shoot", subjectHeight: subjectHeight)
        setup.nodes = nodes
        return PDFEquipmentTables.tables(for: setup)
    }

    @Test("Every table is as wide as the page content and has one cell per column")
    func shape() {
        let all = tables([Equipment(category: .camera), Equipment(category: .light), Equipment(category: .accessory)])

        #expect(all.map(\.title) == ["SUBJECT", "CAMERAS", "LIGHTS", "ACCESSORIES"])
        for table in all {
            #expect(table.columns.reduce(0) { $0 + $1.width } == PDFLayout.contentWidth, "\(table.title) width")
            #expect(table.rows.allSatisfy { $0.cells.count == table.columns.count }, "\(table.title) cells")
        }
    }

    @Test("The camera row has every form field with its unit")
    func camera() throws {
        let camera = Equipment(category: .camera, name: "Sony A7 IV", role: "Main", lens: "50", iso: "100",
                               aperture: "f/8", shutterSpeed: "1/200", whiteBalance: "5600", height: "1.20",
                               tilt: "-5", distance: "1.77", accessories: "Tripod")
        let table = try #require(tables([camera]).first { $0.title == "CAMERAS" })
        let row = try #require(table.rows.first)

        #expect(table.columns.map(\.title) == ["Name and role", "Focal length", "ISO", "Aperture", "Shutter speed",
                                               "White balance", "Height", "Tilt", "Distance to subject"])
        #expect(row.cells == ["Sony A7 IV", "50 mm", "100", "f/8", "1/200", "5600 K", "1.20 m", "-5°", "1.77 m"])
        #expect(row.role == "Main" && row.accessories == "Tripod")
    }

    @Test("The light row has every form field with its unit")
    func light() throws {
        let light = Equipment(
            category: .light,
            name: "Profoto D2",
            role: "Key",
            power: "1/4",
            colorTemp: "5600",
            height: "1,9",
            tilt: "-30",
            horizontalAim: "56",
            distance: "1.78",
            accessories: "Softbox"
        )
        let table = try #require(tables([light]).first { $0.title == "LIGHTS" })
        let row = try #require(table.rows.first)

        #expect(table.columns.map(\.title) == [
            "Name and role", "Power", "Color temperature", "Height", "Tilt", "Distance to subject"
        ])
        #expect(row.cells == ["Profoto D2", "1/4", "5600 K", "1,9 m", "-30°", "1.78 m"])
        #expect(row.role == "Key" && row.accessories == "Softbox")
    }

    @Test("Empty values show a dash, with no unit")
    func emptyValues() throws {
        let row = try #require(tables([Equipment(category: .light)]).last?.rows.first)

        #expect(row.cells.allSatisfy { $0 == "—" })
        #expect(row.role.isEmpty && row.accessories == nil, "No “Accessories: —” line when there are none.")
    }

    @Test("A unit the user typed is not repeated")
    func typedUnit() throws {
        let camera = Equipment(category: .camera, lens: "24-70mm", whiteBalance: "5600K", height: "1.2 m", tilt: "5°")
        let row = try #require(tables([camera]).last?.rows.first)

        #expect(row.cells[1] == "24-70mm" && row.cells[5] == "5600K" && row.cells[6] == "1.2 m" && row.cells[7] == "5°")
    }

    @Test("The subject row has its height; empty tables are left out")
    func subjectOnly() throws {
        let all = tables([], subjectHeight: "0.90")

        #expect(all.map(\.title) == ["SUBJECT"])
        #expect(all.first?.rows.first?.cells == ["Subject", "0.90 m"])
    }

    @Test("Accessories list their name and notes")
    func accessories() {
        let all = tables([Equipment(category: .accessory, name: "Reflector", notes: "Camera right")])

        #expect(all.last?.title == "ACCESSORIES")
        #expect(all.last?.rows.first?.cells == ["Reflector", "Camera right"])
    }

    @Test("Every type has a black PDF icon", arguments: EquipmentCategory.allCases)
    func icons(category: EquipmentCategory) {
        #expect(UIImage(named: category.pdfImageName()) != nil)
    }
}
