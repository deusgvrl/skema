import Foundation
import UIKit
import os

/// Sizes and spacing of the PDF, in points. One place, so no number is hidden inside the drawing code.
enum PDFLayout {
    static let pageSize = CGSize(width: 595, height: 842)
    static let margin: CGFloat = 36

    /// The smallest text anywhere. Content that does not fit at this size goes on an extra page.
    static let minimumFontSize: CGFloat = 9
    static let titleFontSize: CGFloat = 22
    static let subtitleFontSize: CGFloat = 12
    static let sectionFontSize: CGFloat = 14
    static let headingFontSize: CGFloat = 11
    static let bodyFontSize: CGFloat = 10

    static let spacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 16
    static let boxPadding: CGFloat = 8
    static let cellPadding: CGFloat = 4
    static let lineWidth: CGFloat = 0.5

    /// The notes box on page 1 takes a tenth of the page; the diagram box gets the rest (was a quarter, 18 Nov).
    static var notesBoxHeight: CGFloat { pageSize.height / 10 }
    /// About the shape of the page-1 diagram box. The View draws the diagram at this shape (or bigger, see
    /// `DiagramCanvas`), and the PDF fits the picture into the real box.
    static var diagramCanvasSize: CGSize { CGSize(width: contentWidth, height: 540) }
    static let footerHeight: CGFloat = 28

    static let photoColumns = 3
    static let photoRows = 2
    static let photosPerPage = photoColumns * photoRows
    static let photoBoxHeight: CGFloat = 150
    static let photoLabelHeight: CGFloat = 14
    /// The photos of a row share the content width, with one gap between each two.
    static var photoColumnWidth: CGFloat {
        (contentWidth - CGFloat(photoColumns - 1) * spacing) / CGFloat(photoColumns)
    }

    static var contentWidth: CGFloat { pageSize.width - 2 * margin }
    /// Where content must stop so the footer keeps its space.
    static var contentBottom: CGFloat { pageSize.height - margin - footerHeight }
}

/// Builds the templated A4 PDF of a setup (A10-13). Notes, equipment and photos can add pages (A10-98).
final class PDFRenderer {
    private static let signposter = OSSignposter(subsystem: "Skema", category: "PDFExport")
    private static let separator = " · "

    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Makes the PDF. `diagram` is a ready image (A10-99 makes it); nil leaves an empty box.
    func makePDF(for setup: Setup, diagram: UIImage?) -> Data {
        let signpostID = Self.signposter.makeSignpostID()
        let state = Self.signposter.beginInterval("makePDF", id: signpostID)
        defer { Self.signposter.endInterval("makePDF", state) }

        // The footer says "Page N of M", so the first pass only counts pages and the second one draws them.
        let pageCount = render(setup: setup, diagram: diagram, totalPages: 0).pageCount
        return render(setup: setup, diagram: diagram, totalPages: pageCount).data
    }

    private func render(setup: Setup, diagram: UIImage?, totalPages: Int) -> (data: Data, pageCount: Int) {
        let bounds = CGRect(origin: .zero, size: PDFLayout.pageSize)
        var pageCount = 0
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            let pages = PageWriter(context: context, totalPages: totalPages)
            drawFirstPage(setup: setup, diagram: diagram, pages: pages)
            drawEquipment(setup: setup, pages: pages)
            drawReferences(setup: setup, pages: pages)
            pages.finish()
            pageCount = pages.pageNumber
        }
        return (data, pageCount)
    }

    // MARK: - Page 1 and notes

    private func drawFirstPage(setup: Setup, diagram: UIImage?, pages: PageWriter) {
        pages.startPage()
        pages.drawText(setup.setupName, font: .boldSystemFont(ofSize: PDFLayout.titleFontSize))

        let subtitle = [setup.client, setup.project]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: Self.separator)
        if !subtitle.isEmpty {
            pages.drawText(subtitle, font: .systemFont(ofSize: PDFLayout.subtitleFontSize), color: .darkGray)
        }
        if let saved = setup.firstSavedDate {
            let font = UIFont.systemFont(ofSize: PDFLayout.minimumFontSize)
            pages.drawText("Saved \(savedDateText(saved))", font: font, color: .darkGray)
        }
        pages.advance(PDFLayout.sectionSpacing)

        pages.drawHeading("LIGHTING DIAGRAM")
        // The diagram fills page 1 down to where the notes heading and the notes box start.
        let headingFont = UIFont.boldSystemFont(ofSize: PDFLayout.headingFontSize)
        let notesHeading = PageWriter.height(of: "NOTES", font: headingFont, width: PDFLayout.contentWidth)
            + PDFLayout.spacing / 2
        let notesSpace = PDFLayout.sectionSpacing + notesHeading + PDFLayout.notesBoxHeight
        let diagramBox = pages.takeBox(height: PDFLayout.contentBottom - pages.cursorY - notesSpace)
        pages.strokeBox(diagramBox)
        if let diagram {
            let inner = diagramBox.insetBy(dx: PDFLayout.boxPadding, dy: PDFLayout.boxPadding)
            diagram.draw(in: PageWriter.aspectFit(diagram.size, in: inner))
        }
        pages.advance(PDFLayout.sectionSpacing)

        pages.drawHeading("NOTES")
        drawNotes(setup.notes, pages: pages)
    }

    /// Fills the box on the current page; whatever does not fit continues on following pages.
    private func drawNotes(_ notes: String, pages: PageWriter) {
        var remaining = NSAttributedString(
            string: notes,
            attributes: [.font: UIFont.systemFont(ofSize: PDFLayout.bodyFontSize), .foregroundColor: UIColor.black]
        )
        while true {
            let box = pages.takeBox(height: PDFLayout.contentBottom - pages.cursorY)
            pages.strokeBox(box)
            let inner = box.insetBy(dx: PDFLayout.boxPadding, dy: PDFLayout.boxPadding)
            let fitted = PageWriter.drawFitting(remaining, in: inner)
            guard fitted < remaining.length else { return }
            let rest = NSRange(location: fitted, length: remaining.length - fitted)
            remaining = remaining.attributedSubstring(from: rest)
            pages.startPage()
            pages.drawHeading("Notes (continued)")
        }
    }

    private func savedDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    // MARK: - Equipment tables

    private func drawEquipment(setup: Setup, pages: PageWriter) {
        // Equipment always starts on a new page, after any notes pages.
        pages.startPage()
        pages.drawText("Equipment Details", font: .boldSystemFont(ofSize: PDFLayout.sectionFontSize))
        let summary = PDFEquipmentTables.summary(for: setup, separator: Self.separator)
        if !summary.isEmpty {
            pages.drawText(summary, font: .systemFont(ofSize: PDFLayout.bodyFontSize), color: .darkGray)
        }
        pages.advance(PDFLayout.spacing)
        for table in PDFEquipmentTables.tables(for: setup) {
            pages.drawTable(table)
        }
    }

    // MARK: - References

    private func drawReferences(setup: Setup, pages: PageWriter) {
        let photos = DisplayOrder.photos(setup.referenceImages)
        guard !photos.isEmpty else { return }

        // The first block (up to `photosPerPage`) goes under the tables only if it fits there; otherwise on a new page.
        let cellHeight = PDFLayout.photoBoxHeight + PDFLayout.photoLabelHeight + PDFLayout.spacing
        let firstCount = min(photos.count, PDFLayout.photosPerPage)
        let firstRows = (firstCount + PDFLayout.photoColumns - 1) / PDFLayout.photoColumns
        let blockHeight = CGFloat(firstRows) * cellHeight
        let headingHeight = PDFLayout.sectionFontSize + PDFLayout.sectionSpacing
        if pages.cursorY + headingHeight + blockHeight > PDFLayout.contentBottom {
            pages.startPage()
        }
        let heading = "References · \(photos.count) \(photos.count == 1 ? "photo" : "photos")"
        pages.drawText(heading, font: .boldSystemFont(ofSize: PDFLayout.sectionFontSize))
        pages.advance(PDFLayout.spacing)

        for start in stride(from: 0, to: photos.count, by: PDFLayout.photosPerPage) {
            if start > 0 { pages.startPage() }
            let group = photos[start..<min(start + PDFLayout.photosPerPage, photos.count)]
            drawPhotoGrid(Array(group), firstNumber: start + 1, pages: pages)
        }
    }

    private func drawPhotoGrid(_ group: [ReferenceImage], firstNumber: Int, pages: PageWriter) {
        let columnWidth = PDFLayout.photoColumnWidth
        let cellHeight = PDFLayout.photoBoxHeight + PDFLayout.photoLabelHeight + PDFLayout.spacing
        let top = pages.cursorY
        for (offset, photo) in group.enumerated() {
            let column = offset % PDFLayout.photoColumns
            let row = offset / PDFLayout.photoColumns
            let origin = CGPoint(
                x: PDFLayout.margin + CGFloat(column) * (columnWidth + PDFLayout.spacing),
                y: top + CGFloat(row) * cellHeight
            )
            let box = CGRect(x: origin.x, y: origin.y, width: columnWidth, height: PDFLayout.photoBoxHeight)
            pages.strokeBox(box)
            if let image = UIImage(data: photo.imageData) {
                let inner = box.insetBy(dx: PDFLayout.boxPadding, dy: PDFLayout.boxPadding)
                image.draw(in: PageWriter.aspectFit(image.size, in: inner))
            }
            let labelRect = CGRect(x: origin.x, y: box.maxY + 1, width: columnWidth, height: PDFLayout.photoLabelHeight)
            let label = "Reference \(firstNumber + offset)"
            PageWriter.draw(label, font: .systemFont(ofSize: PDFLayout.bodyFontSize), color: .black, in: labelRect)
        }
        let rows = (group.count + PDFLayout.photoColumns - 1) / PDFLayout.photoColumns
        pages.advance(CGFloat(rows) * cellHeight)
    }
}
