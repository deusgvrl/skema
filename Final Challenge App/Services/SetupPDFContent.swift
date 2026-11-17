//
//  SetupPDFContent.swift
//  Final Challenge App
//
//  Everything the shared A4 PDF shows, as plain strings, and how it splits into pages
//  (Sketch R15q page 1 "Diagram + Notes", R15q·2 page 2 "Equipment + References").
//

import CoreGraphics
import Foundation

struct SetupPDFContent {
    struct Row: Equatable {
        let id: String
        let name: String
        let role: String
        let accessories: String
        let distance: String
        /// "1.8 m · 35° · 135°" — height · tilt · aim.
        let placement: String
        let settings: String
    }

    struct Photo {
        let imageData: Data
        let caption: String
        let detail: String
    }

    /// The rows and photos one details page (page 2 onwards) holds.
    struct DetailPage: Equatable {
        let rows: Range<Int>
        let photos: Range<Int>
    }

    static let missing = "—"

    let title: String
    let subtitle: String
    let savedLine: String
    let notes: String
    let summary: String
    let rows: [Row]
    let photos: [Photo]
    let fileName: String

    init(setup: Setup) {
        let name = setup.setupName.trimmingCharacters(in: .whitespacesAndNewlines)
        title = name.isEmpty ? "Untitled Setup" : name
        subtitle = [setup.client, setup.project]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        savedLine = "Saved \(setup.createdAt.formatted(.dateTime.day().month(.abbreviated).year()))"
        notes = setup.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        summary = Self.summary(for: setup.nodes)
        fileName = Self.fileName(for: setup.setupName)

        var rows = setup.nodes.inChipOrder.map(Self.row(for:))
        let subjectHeight = setup.subjectHeight.trimmingCharacters(in: .whitespaces)
        if !subjectHeight.isEmpty {
            rows.append(Row(id: "S", name: "Subject", role: "", accessories: Self.missing,
                            distance: Self.missing, placement: "\(subjectHeight) m", settings: Self.missing))
        }
        self.rows = rows

        photos = setup.referenceImages
            .sorted { $0.createdAt < $1.createdAt }
            .enumerated()
            .map { index, reference in
                Photo(imageData: reference.imageData, caption: "Reference \(index + 1)",
                      detail: "Added \(reference.formattedDateString)")
            }
    }

    // MARK: - Strings

    static func fileName(for setupName: String) -> String {
        let cleaned = setupName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(cleaned.isEmpty ? "Untitled Setup" : cleaned).pdf"
    }

    private static func summary(for nodes: [Equipment]) -> String {
        func count(_ category: EquipmentCategory, _ one: String, _ many: String) -> String? {
            let total = nodes.filter { $0.category == category }.count
            return total == 0 ? nil : "\(total) \(total == 1 ? one : many)"
        }
        let parts = [
            count(.light, "light", "lights"),
            count(.accessory, "accessory", "accessories"),
            count(.camera, "camera", "cameras")
        ].compactMap { $0 }
        return parts.isEmpty ? "No equipment" : parts.joined(separator: " · ")
    }

    private static func row(for equipment: Equipment) -> Row {
        let role: String
        let settings: String
        switch equipment.category {
        case .light:
            role = equipment.role.trimmed
            settings = joined([equipment.power.trimmed, withUnit(equipment.colorTemp, " K")])
        case .camera:
            role = [equipment.role.trimmed, equipment.lens.trimmed].filter { !$0.isEmpty }.joined(separator: " · ")
            settings = joined([
                prefixed(equipment.iso, "ISO "),
                aperture(equipment.aperture),
                equipment.shutterSpeed.trimmed,
                withUnit(equipment.whiteBalance, " K")
            ])
        case .accessory:
            role = equipment.role.trimmed
            settings = missing
        }
        let placementParts = [withUnit(equipment.height, " m"), withUnit(equipment.tilt, "°"), withUnit(equipment.horizontalAim, "°")]
        let placement = placementParts.allSatisfy(\.isEmpty)
            ? missing
            : placementParts.map { $0.isEmpty ? missing : $0 }.joined(separator: " · ")
        return Row(
            id: equipment.label.trimmed,
            name: equipment.name.trimmed.isEmpty ? equipment.displayName : equipment.name.trimmed,
            role: role,
            accessories: equipment.accessories.trimmed.isEmpty ? missing : equipment.accessories.trimmed,
            distance: withUnit(equipment.distance, " m").isEmpty ? missing : withUnit(equipment.distance, " m"),
            placement: placement,
            settings: settings
        )
    }

    private static func withUnit(_ value: String, _ unit: String) -> String {
        value.trimmed.isEmpty ? "" : value.trimmed + unit
    }

    private static func prefixed(_ value: String, _ prefix: String) -> String {
        value.trimmed.isEmpty ? "" : prefix + value.trimmed
    }

    private static func aperture(_ value: String) -> String {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty else { return "" }
        return trimmed.lowercased().hasPrefix("f") ? trimmed : "f/\(trimmed)"
    }

    private static func joined(_ parts: [String]) -> String {
        let present = parts.filter { !$0.isEmpty }
        return present.isEmpty ? missing : present.joined(separator: " · ")
    }

    // MARK: - Layout

    /// Page heights in points (A4 595 × 842, 40 top, 56 bottom for the footer).
    enum Metrics {
        static let pageSize = CGSize(width: 595, height: 842)
        static let margin: CGFloat = 40
        static let contentHeight: CGFloat = 842 - 40 - 56
        static let firstDetailsHeader: CGFloat = 70
        static let continuedHeader: CGFloat = 40
        static let tableHeader: CGFloat = 22
        static let row: CGFloat = 30
        static let referencesHeader: CGFloat = 26
        /// One line of two photos: 130 image + 28 caption.
        static let photoLine: CGFloat = 158
    }

    /// Splits the equipment table and the reference photos over pages 2, 3, …
    static func detailPages(rowCount: Int, photoCount: Int) -> [DetailPage] {
        var pages: [DetailPage] = []
        var nextRow = 0
        var nextPhoto = 0
        repeat {
            var used = pages.isEmpty ? Metrics.firstDetailsHeader : Metrics.continuedHeader
            let firstRow = nextRow
            if nextRow < rowCount {
                used += Metrics.tableHeader
                while nextRow < rowCount && used + Metrics.row <= Metrics.contentHeight {
                    used += Metrics.row
                    nextRow += 1
                }
            }
            let firstPhoto = nextPhoto
            if nextRow == rowCount && nextPhoto < photoCount
                && used + Metrics.referencesHeader + Metrics.photoLine <= Metrics.contentHeight {
                used += Metrics.referencesHeader
                while nextPhoto < photoCount && used + Metrics.photoLine <= Metrics.contentHeight {
                    used += Metrics.photoLine
                    nextPhoto = min(nextPhoto + 2, photoCount)
                }
            }
            pages.append(DetailPage(rows: firstRow..<nextRow, photos: firstPhoto..<nextPhoto))
        } while nextRow < rowCount || nextPhoto < photoCount
        return pages
    }

    /// Room around an item's centre for its icon and the label under it ("C1 Main camera").
    static let diagramReachX: CGFloat = 70
    static let diagramReachY: CGFloat = 60

    /// Zoom for the diagram so every item (plus room for its label) fits the box; never above 1×,
    /// never below the diagram's own 0.3× minimum.
    static func diagramZoom(for positions: [CGPoint], in box: CGSize) -> CGFloat {
        guard !positions.isEmpty else { return 1 }
        let reachX = (positions.map { abs($0.x) }.max() ?? 0) + diagramReachX
        let reachY = (positions.map { abs($0.y) }.max() ?? 0) + diagramReachY
        let zoom = min(1, (box.width / 2) / reachX, (box.height / 2) / reachY)
        return max(0.3, zoom)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
