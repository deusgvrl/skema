import Foundation
import UIKit

/// Keeps the page number and the next free line while the PDF is drawn. Draws the footer of every page.
final class PageWriter {
    private let context: UIGraphicsPDFRendererContext
    private let totalPages: Int
    private(set) var pageNumber = 0
    private(set) var cursorY = PDFLayout.margin

    init(context: UIGraphicsPDFRendererContext, totalPages: Int) {
        self.context = context
        self.totalPages = totalPages
    }

    func startPage() {
        if pageNumber > 0 { drawFooter() }
        context.beginPage()
        pageNumber += 1
        cursorY = PDFLayout.margin
    }

    func finish() {
        if pageNumber > 0 { drawFooter() }
    }

    func advance(_ distance: CGFloat) {
        cursorY += distance
    }

    // MARK: Text

    func drawText(_ text: String, font: UIFont, color: UIColor = .black) {
        let height = Self.height(of: text, font: font, width: PDFLayout.contentWidth)
        let rect = CGRect(x: PDFLayout.margin, y: cursorY, width: PDFLayout.contentWidth, height: height)
        Self.draw(text, font: font, color: color, in: rect)
        cursorY += height + PDFLayout.spacing / 2
    }

    func drawHeading(_ text: String) {
        drawText(text, font: .boldSystemFont(ofSize: PDFLayout.headingFontSize), color: .darkGray)
    }

    static func height(of text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin,
            attributes: [.font: font],
            context: nil
        )
        return ceil(bounds.height)
    }

    static func draw(_ text: String, font: UIFont, color: UIColor, in rect: CGRect) {
        (text as NSString).draw(
            with: rect,
            options: .usesLineFragmentOrigin,
            attributes: [.font: font, .foregroundColor: color],
            context: nil
        )
    }

    /// Draws as many whole lines as fit in `rect` and returns how many characters that was.
    /// At least one character is always taken, so a very small box cannot loop forever.
    static func drawFitting(_ text: NSAttributedString, in rect: CGRect) -> Int {
        guard text.length > 0 else { return 0 }
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: rect.size)
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let glyphs = layout.glyphRange(for: container)
        layout.drawGlyphs(forGlyphRange: glyphs, at: rect.origin)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        return max(characters.length, 1)
    }

    // MARK: Boxes and images

    /// Reserves a full-width box at the cursor and moves the cursor under it.
    func takeBox(height: CGFloat) -> CGRect {
        let box = CGRect(x: PDFLayout.margin, y: cursorY, width: PDFLayout.contentWidth, height: max(height, 0))
        cursorY += box.height
        return box
    }

    func strokeBox(_ rect: CGRect) {
        UIColor.gray.setStroke()
        let path = UIBezierPath(rect: rect)
        path.lineWidth = PDFLayout.lineWidth
        path.stroke()
    }

    /// The largest rect with the image's shape that fits inside `rect`, centred.
    static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: rect.midX - fitted.width / 2,
            y: rect.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    // MARK: Footer

    private func drawFooter() {
        let font = UIFont.systemFont(ofSize: PDFLayout.minimumFontSize)
        let top = PDFLayout.pageSize.height - PDFLayout.margin - PDFLayout.footerHeight
        let lineHeight = PDFLayout.footerHeight / 2
        let note = "Skema Photo · Heights are measured from the floor, distances to the subject. "
            + "Values from the scan are estimates."
        let noteRect = CGRect(x: PDFLayout.margin, y: top, width: PDFLayout.contentWidth, height: lineHeight)
        Self.draw(note, font: font, color: .darkGray, in: noteRect)

        let style = NSMutableParagraphStyle()
        style.alignment = .right
        let numberRect = CGRect(
            x: PDFLayout.margin, y: top + lineHeight, width: PDFLayout.contentWidth, height: lineHeight
        )
        ("Page \(pageNumber) of \(totalPages)" as NSString).draw(
            in: numberRect,
            withAttributes: [.font: font, .foregroundColor: UIColor.darkGray, .paragraphStyle: style]
        )
    }
}
