import UIKit

/// One table of the PDF: a title, column headers and rows.
struct PDFTable {
    struct Column {
        let title: String
        let width: CGFloat
    }

    struct Row {
        /// One per column. The first one is the item's name, in bold.
        let cells: [String]
        /// Under the name, in grey. Empty leaves the line out.
        var role = ""
        /// A full-width line under the cells. Nil for tables without one.
        var accessories: String?
    }

    let title: String
    let columns: [Column]
    let rows: [Row]
}

extension PageWriter {
    private static let font = UIFont.systemFont(ofSize: PDFLayout.minimumFontSize)
    private static let boldFont = UIFont.boldSystemFont(ofSize: PDFLayout.minimumFontSize)

    /// Draws the table at the cursor. The title and headers stay with the first row, and are repeated on every page
    /// the table continues on.
    func drawTable(_ table: PDFTable) {
        guard let firstRow = table.rows.first else { return }
        let titleHeight = Self.titleHeight(table.title)
        let headerHeight = Self.headerHeight(table.columns)
        let firstHeight = Self.height(of: firstRow, columns: table.columns)
        if cursorY + titleHeight + headerHeight + firstHeight > PDFLayout.contentBottom {
            startPage()
        }
        drawHeading(table.title)
        drawHeader(table.columns, height: headerHeight)
        for row in table.rows {
            let height = Self.height(of: row, columns: table.columns)
            if cursorY + height > PDFLayout.contentBottom {
                startPage()
                drawHeading("\(table.title) (continued)")
                drawHeader(table.columns, height: headerHeight)
            }
            draw(row, columns: table.columns, height: height)
        }
        advance(PDFLayout.sectionSpacing)
    }

    // MARK: Sizes

    private static func titleHeight(_ title: String) -> CGFloat {
        let font = UIFont.boldSystemFont(ofSize: PDFLayout.headingFontSize)
        return height(of: title, font: font, width: PDFLayout.contentWidth) + PDFLayout.spacing / 2
    }

    private static func headerHeight(_ columns: [PDFTable.Column]) -> CGFloat {
        let tallest = columns.map { height(of: $0.title, font: boldFont, width: textWidth($0)) }.max() ?? 0
        return tallest + 2 * PDFLayout.cellPadding
    }

    private static func height(of row: PDFTable.Row, columns: [PDFTable.Column]) -> CGFloat {
        cellsHeight(of: row, columns: columns) + accessoriesHeight(of: row) + 2 * PDFLayout.cellPadding
    }

    /// The tallest cell; the name cell also holds the role.
    private static func cellsHeight(of row: PDFTable.Row, columns: [PDFTable.Column]) -> CGFloat {
        zip(row.cells, columns).enumerated().map { index, pair in
            let (cell, column) = pair
            guard index == 0 else { return height(of: cell, font: font, width: textWidth(column)) }
            let name = height(of: cell, font: boldFont, width: textWidth(column))
            return row.role.isEmpty ? name : name + height(of: row.role, font: font, width: textWidth(column))
        }.max() ?? 0
    }

    private static func accessoriesHeight(of row: PDFTable.Row) -> CGFloat {
        guard let text = accessoriesText(row) else { return 0 }
        let width = PDFLayout.contentWidth - 2 * PDFLayout.cellPadding
        return height(of: text, font: font, width: width) + PDFLayout.cellPadding
    }

    private static func accessoriesText(_ row: PDFTable.Row) -> String? {
        row.accessories.map { "Accessories: \($0)" }
    }

    private static func textWidth(_ column: PDFTable.Column) -> CGFloat {
        column.width - 2 * PDFLayout.cellPadding
    }

    // MARK: Drawing

    private func drawHeader(_ columns: [PDFTable.Column], height: CGFloat) {
        UIColor(white: 0.94, alpha: 1).setFill()
        UIRectFill(CGRect(x: PDFLayout.margin, y: cursorY, width: PDFLayout.contentWidth, height: height))
        var columnX = PDFLayout.margin
        for column in columns {
            let rect = CGRect(x: columnX + PDFLayout.cellPadding, y: cursorY + PDFLayout.cellPadding,
                              width: Self.textWidth(column), height: height - 2 * PDFLayout.cellPadding)
            Self.draw(column.title, font: Self.boldFont, color: .darkGray, in: rect)
            columnX += column.width
        }
        advance(height)
        drawLine()
    }

    private func draw(_ row: PDFTable.Row, columns: [PDFTable.Column], height: CGFloat) {
        let top = cursorY + PDFLayout.cellPadding
        let cellsHeight = Self.cellsHeight(of: row, columns: columns)
        var columnX = PDFLayout.margin
        for (index, (cell, column)) in zip(row.cells, columns).enumerated() {
            var rect = CGRect(x: columnX + PDFLayout.cellPadding, y: top,
                              width: Self.textWidth(column), height: cellsHeight)
            Self.draw(cell, font: index == 0 ? Self.boldFont : Self.font, color: .black, in: rect)
            if index == 0, !row.role.isEmpty {
                rect.origin.y += Self.height(of: cell, font: Self.boldFont, width: rect.width)
                Self.draw(row.role, font: Self.font, color: .darkGray, in: rect)
            }
            columnX += column.width
        }
        if let text = Self.accessoriesText(row) {
            let rect = CGRect(x: PDFLayout.margin + PDFLayout.cellPadding, y: top + cellsHeight + PDFLayout.cellPadding,
                              width: PDFLayout.contentWidth - 2 * PDFLayout.cellPadding,
                              height: Self.accessoriesHeight(of: row))
            Self.draw(text, font: Self.font, color: .darkGray, in: rect)
        }
        advance(height)
        drawLine()
    }

    private func drawLine() {
        let line = UIBezierPath()
        line.move(to: CGPoint(x: PDFLayout.margin, y: cursorY))
        line.addLine(to: CGPoint(x: PDFLayout.margin + PDFLayout.contentWidth, y: cursorY))
        line.lineWidth = PDFLayout.lineWidth
        UIColor.lightGray.setStroke()
        line.stroke()
    }
}
