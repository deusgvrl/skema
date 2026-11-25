import Foundation

/// The tables of the PDF's Equipment Details, most important first: Subject, Camera, Lighting and Accessories, with
/// the same fields and units as the forms. Camera, Lighting and Accessories are left out when the setup has none.
enum PDFEquipmentTables {
    private static let emptyValue = "—"

    static func tables(for setup: Setup) -> [PDFTable] {
        let items = DisplayOrder.equipment(setup.nodes)
        return [
            subject(height: setup.subjectHeight),
            cameras(items.filter { $0.category == .camera }),
            lights(items.filter { $0.category == .light }),
            accessories(items.filter { $0.category == .accessory })
        ].filter { !$0.rows.isEmpty }
    }

    /// "1 camera · 2 lights · 1 accessory"; types with no items are left out.
    static func summary(for setup: Setup, separator: String) -> String {
        [EquipmentCategory.camera, .light, .accessory].compactMap { category in
            let count = setup.nodes.filter { $0.category == category }.count
            return count == 0 ? nil : "\(count) \(noun(for: category, isPlural: count > 1))"
        }.joined(separator: separator)
    }

    private static func noun(for category: EquipmentCategory, isPlural: Bool) -> String {
        switch category {
        case .camera: isPlural ? "cameras" : "camera"
        case .light: isPlural ? "lights" : "light"
        case .accessory: isPlural ? "accessories" : "accessory"
        }
    }

    // MARK: Tables (the widths of each add up to `PDFLayout.contentWidth` = 523)

    private static func cameras(_ items: [Equipment]) -> PDFTable {
        PDFTable(
            title: "CAMERA",
            columns: [
                .init(title: "Name / role", width: 160),
                .init(title: "Lens", width: 42),
                .init(title: "ISO", width: 38),
                .init(title: "Aperture", width: 50),
                .init(title: "Shutter speed", width: 44),
                .init(title: "White balance", width: 48),
                .init(title: "Height", width: 44),
                .init(title: "Tilt", width: 37),
                .init(title: "Distance to subject", width: 60)
            ],
            rows: items.map { item in
                row(for: item, values: [
                    value(item.lens, unit: " mm"), value(item.iso), value(item.aperture), value(item.shutterSpeed),
                    value(item.whiteBalance, unit: " K"), value(item.height, unit: " m"),
                    value(item.tilt, unit: "°"), value(item.distance, unit: " m")
                ])
            }
        )
    }

    private static func lights(_ items: [Equipment]) -> PDFTable {
        PDFTable(
            title: "LIGHTING",
            columns: [
                .init(title: "Name / role", width: 160),
                .init(title: "Power", width: 55),
                .init(title: "Color temperature", width: 78),
                .init(title: "Height", width: 55),
                .init(title: "Tilt", width: 50),
                .init(title: "Distance to subject", width: 125)
            ],
            rows: items.map { item in
                row(for: item, values: [
                    value(item.power), value(item.colorTemp, unit: " K"), value(item.height, unit: " m"),
                    value(item.tilt, unit: "°"),
                    value(item.distance, unit: " m")
                ])
            }
        )
    }

    private static func subject(height: String) -> PDFTable {
        PDFTable(
            title: "SUBJECT",
            columns: [.init(title: "Name", width: 160), .init(title: "Height from floor", width: 363)],
            rows: [.init(cells: ["Subject", value(height, unit: " m")])]
        )
    }

    private static func accessories(_ items: [Equipment]) -> PDFTable {
        PDFTable(
            title: "ACCESSORIES",
            columns: [.init(title: "Name", width: 160), .init(title: "Notes", width: 363)],
            rows: items.map { .init(cells: [value($0.name), value($0.notes)]) }
        )
    }

    // MARK: Values

    private static func row(for item: Equipment, values: [String]) -> PDFTable.Row {
        PDFTable.Row(
            cells: [value(item.name)] + values,
            role: item.role.trimmingCharacters(in: .whitespacesAndNewlines),
            accessories: value(item.accessories)
        )
    }

    /// The value with its unit, or a dash when empty. The unit is only added after a number, so one the user typed
    /// ("24-70mm") is not repeated.
    private static func value(_ text: String, unit: String = "") -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return emptyValue }
        return last.isNumber ? trimmed + unit : trimmed
    }
}
