//
//  PDFRenderer.swift
//  Final Challenge App
//
//  Draws the shared A4 PDF of a setup (Sketch R15q page 1, R15q·2 page 2 · A10-13).
//  Paper is always light, so colors are the design tokens resolved in light.
//

import SwiftUI
import UIKit

struct PDFRenderer {
    private typealias Metrics = SetupPDFContent.Metrics

    /// Builds the PDF. `diagram` is the lighting diagram already rendered (light appearance).
    func render(_ content: SetupPDFContent, diagram: UIImage?) -> Data {
        let detailPages = SetupPDFContent.detailPages(rowCount: content.rows.count, photoCount: content.photos.count)
        let pageCount = 1 + detailPages.count
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: Metrics.pageSize))
        return renderer.pdfData { context in
            context.beginPage()
            drawOverview(content, diagram: diagram, pageCount: pageCount)
            for (index, page) in detailPages.enumerated() {
                context.beginPage()
                drawDetails(content, page: page, isFirst: index == 0, pageNumber: index + 2, pageCount: pageCount)
            }
        }
    }

    /// Writes the PDF to a fresh temporary folder under `name`, ready for the share sheet.
    func writeFile(_ data: Data, named name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedPDF", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Page 1: diagram and notes

    private func drawOverview(_ content: SetupPDFContent, diagram: UIImage?, pageCount: Int) {
        let margin = Metrics.margin
        let width = Metrics.pageSize.width - margin * 2
        Draw.text(content.title, at: CGPoint(x: margin, y: margin), width: width - 120, font: .bold(20))
        Draw.text(content.savedLine, at: CGPoint(x: margin, y: margin + 6), width: width,
                  font: .regular(8), color: Palette.secondary, alignment: .right)
        if !content.subtitle.isEmpty {
            Draw.text(content.subtitle, at: CGPoint(x: margin, y: margin + 28), width: width,
                      font: .regular(9), color: Palette.secondary)
        }

        Draw.sectionLabel("LIGHTING DIAGRAM", at: CGPoint(x: margin, y: 96))
        let diagramBox = CGRect(x: margin, y: 110, width: width, height: 380)
        Draw.box(diagramBox, fill: Palette.canvas)
        if let diagram {
            Draw.image(diagram, in: diagramBox.insetBy(dx: 1, dy: 1), fill: false)
        }

        if !content.notes.isEmpty {
            Draw.sectionLabel("NOTES", at: CGPoint(x: margin, y: diagramBox.maxY + 18))
            let textWidth = width - 24
            let textHeight = Draw.height(of: content.notes, width: textWidth, font: .regular(9))
            let maxHeight = Metrics.pageSize.height - 70 - (diagramBox.maxY + 32)
            let notesBox = CGRect(x: margin, y: diagramBox.maxY + 32, width: width,
                                  height: min(maxHeight, max(56, textHeight + 24)))
            Draw.box(notesBox, fill: Palette.canvas)
            Draw.text(content.notes, in: notesBox.insetBy(dx: 12, dy: 12), font: .regular(9))
        }

        drawFooter(left: "Lighting Memory · \(content.title)", pageNumber: 1, pageCount: pageCount)
    }

    // MARK: - Page 2+: equipment and references

    private func drawDetails(_ content: SetupPDFContent, page: SetupPDFContent.DetailPage,
                             isFirst: Bool, pageNumber: Int, pageCount: Int) {
        let margin = Metrics.margin
        let width = Metrics.pageSize.width - margin * 2
        var cursor = margin
        Draw.text(content.title, at: CGPoint(x: margin, y: cursor), width: width, font: .regular(8), color: Palette.secondary)
        if isFirst {
            Draw.text("Equipment Details", at: CGPoint(x: margin, y: cursor + 14), width: width, font: .bold(18))
            Draw.text(content.summary, at: CGPoint(x: margin, y: cursor + 40), width: width,
                      font: .regular(9), color: Palette.secondary)
            cursor += Metrics.firstDetailsHeader
        } else {
            cursor += Metrics.continuedHeader
        }

        if !page.rows.isEmpty {
            cursor = EquipmentTable.draw(Array(content.rows[page.rows]), top: cursor, left: margin, width: width)
        }
        if !page.photos.isEmpty {
            let isFirstPhotoPage = page.photos.lowerBound == 0
            if isFirstPhotoPage {
                Draw.sectionLabel("REFERENCES · \(content.photos.count) \(content.photos.count == 1 ? "PHOTO" : "PHOTOS")",
                                  at: CGPoint(x: margin, y: cursor + 8))
            }
            cursor += Metrics.referencesHeader
            drawPhotos(Array(content.photos[page.photos]), top: cursor, left: margin, width: width)
        }

        drawFooter(
            left: "Lighting Memory · Height, tilt and aim are relative to the subject. Values from the scan are estimates.",
            pageNumber: pageNumber,
            pageCount: pageCount
        )
    }

    private func drawPhotos(_ photos: [SetupPDFContent.Photo], top: CGFloat, left: CGFloat, width: CGFloat) {
        let gap: CGFloat = 16
        let cellWidth = (width - gap) / 2
        for (index, photo) in photos.enumerated() {
            let origin = CGPoint(x: left + CGFloat(index % 2) * (cellWidth + gap),
                                 y: top + CGFloat(index / 2) * Metrics.photoLine)
            let imageRect = CGRect(x: origin.x, y: origin.y, width: cellWidth, height: 130)
            if let image = UIImage(data: photo.imageData) {
                Draw.image(image, in: imageRect, fill: true)
            } else {
                Draw.box(imageRect, fill: Palette.canvas)
            }
            Draw.text(photo.caption, at: CGPoint(x: origin.x, y: imageRect.maxY + 4), width: cellWidth, font: .semibold(8))
            Draw.text(photo.detail, at: CGPoint(x: origin.x, y: imageRect.maxY + 15), width: cellWidth,
                      font: .regular(7), color: Palette.secondary)
        }
    }

    private func drawFooter(left: String, pageNumber: Int, pageCount: Int) {
        let margin = Metrics.margin
        let width = Metrics.pageSize.width - margin * 2
        let lineY = Metrics.pageSize.height - 46
        Draw.line(from: CGPoint(x: margin, y: lineY), to: CGPoint(x: margin + width, y: lineY))
        Draw.text(left, at: CGPoint(x: margin, y: lineY + 8), width: width - 70, font: .regular(7), color: Palette.secondary)
        Draw.text("Page \(pageNumber) of \(pageCount)", at: CGPoint(x: margin, y: lineY + 8), width: width,
                  font: .regular(7), color: Palette.secondary, alignment: .right)
    }
}

// MARK: - Equipment table

private enum EquipmentTable {
    /// Column titles and widths (sum 515 = A4 width minus margins).
    static let columns: [(title: String, width: CGFloat, alignment: NSTextAlignment)] = [
        ("ID", 30, .left), ("EQUIPMENT", 128, .left), ("ACCESSORIES", 95, .left),
        ("DISTANCE", 50, .left), ("HEIGHT · TILT · AIM", 110, .left), ("SETTINGS", 102, .right)
    ]

    /// Draws the header and rows; returns the y below the table.
    static func draw(_ rows: [SetupPDFContent.Row], top: CGFloat, left: CGFloat, width: CGFloat) -> CGFloat {
        var columnX = left
        for column in columns {
            Draw.text(column.title, at: CGPoint(x: columnX, y: top + 6), width: column.width - 4,
                      font: .semibold(6.5), color: Palette.secondary, alignment: column.alignment)
            columnX += column.width
        }
        var cursor = top + SetupPDFContent.Metrics.tableHeader
        Draw.line(from: CGPoint(x: left, y: cursor), to: CGPoint(x: left + width, y: cursor))
        for row in rows {
            drawRow(row, top: cursor, left: left)
            cursor += SetupPDFContent.Metrics.row
            Draw.line(from: CGPoint(x: left, y: cursor), to: CGPoint(x: left + width, y: cursor))
        }
        return cursor
    }

    private static func drawRow(_ row: SetupPDFContent.Row, top: CGFloat, left: CGFloat) {
        let pill = CGRect(x: left, y: top + 8, width: 20, height: 14)
        Draw.box(pill, fill: Palette.canvas, radius: 4, stroke: false)
        Draw.text(row.id, at: CGPoint(x: pill.minX, y: pill.minY + 3), width: pill.width, font: .semibold(6.5),
                  alignment: .center)

        var columnX = left + columns[0].width
        Draw.text(row.name, at: CGPoint(x: columnX, y: top + 5), width: columns[1].width - 6, font: .semibold(8.5))
        if !row.role.isEmpty {
            Draw.text(row.role, at: CGPoint(x: columnX, y: top + 17), width: columns[1].width - 6,
                      font: .regular(7), color: Palette.secondary)
        }
        columnX += columns[1].width
        let cells = [row.accessories, row.distance, row.placement, row.settings]
        for (offset, value) in cells.enumerated() {
            let column = columns[offset + 2]
            Draw.text(value, at: CGPoint(x: columnX, y: top + 10), width: column.width - 4, font: .regular(8),
                      alignment: column.alignment)
            columnX += column.width
        }
    }
}

// MARK: - Drawing helpers

private enum Palette {
    static let light = UITraitCollection(userInterfaceStyle: .light)
    static let primary = UIColor(DesignTokens.textPrimary).resolvedColor(with: light)
    static let secondary = UIColor(DesignTokens.textSecondary).resolvedColor(with: light)
    static let canvas = UIColor(DesignTokens.pageBackground).resolvedColor(with: light)
    static let hairline = UIColor(DesignTokens.diagramSubjectBorder).resolvedColor(with: light)
}

private extension UIFont {
    static func regular(_ size: CGFloat) -> UIFont { .systemFont(ofSize: size) }
    static func semibold(_ size: CGFloat) -> UIFont { .systemFont(ofSize: size, weight: .semibold) }
    static func bold(_ size: CGFloat) -> UIFont { .systemFont(ofSize: size, weight: .bold) }
}

private enum Draw {
    static func attributes(_ font: UIFont, _ color: UIColor, _ alignment: NSTextAlignment) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    /// One line, truncated to `width`.
    static func text(_ string: String, at point: CGPoint, width: CGFloat, font: UIFont,
                     color: UIColor = Palette.primary, alignment: NSTextAlignment = .left) {
        let rect = CGRect(x: point.x, y: point.y, width: width, height: font.lineHeight + 2)
        (string as NSString).draw(in: rect, withAttributes: attributes(font, color, alignment))
    }

    /// Wrapped text inside `rect`.
    static func text(_ string: String, in rect: CGRect, font: UIFont, color: UIColor = Palette.primary) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2
        (string as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                  attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph],
                                  context: nil)
    }

    static func height(of string: String, width: CGFloat, font: UIFont) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let bounds = (string as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin,
            attributes: [.font: font, .paragraphStyle: paragraph],
            context: nil
        )
        return ceil(bounds.height)
    }

    static func sectionLabel(_ string: String, at point: CGPoint) {
        var attributes = attributes(.semibold(7), Palette.secondary, .left)
        attributes[.kern] = 0.6
        (string as NSString).draw(at: point, withAttributes: attributes)
    }

    static func box(_ rect: CGRect, fill: UIColor, radius: CGFloat = 10, stroke: Bool = true) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        fill.setFill()
        path.fill()
        if stroke {
            Palette.hairline.setStroke()
            path.lineWidth = 0.5
            path.stroke()
        }
    }

    static func line(from start: CGPoint, to end: CGPoint) {
        let path = UIBezierPath()
        path.move(to: start)
        path.addLine(to: end)
        path.lineWidth = 0.5
        Palette.hairline.setStroke()
        path.stroke()
    }

    /// Draws `image` aspect-fit (`fill == false`) or aspect-fill and clipped (`fill == true`) in `rect`.
    static func image(_ image: UIImage, in rect: CGRect, fill: Bool) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = fill
            ? max(rect.width / image.size.width, rect.height / image.size.height)
            : min(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawRect = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                              width: size.width, height: size.height)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: fill ? 6 : 10).addClip()
        image.draw(in: drawRect)
        context.restoreGState()
    }
}
