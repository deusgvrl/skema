import Foundation
import MeasureKit

/// ASCII PLY files for the raw-data export: one vertex per line, values split by one space.
/// Extra vertex properties (look, item, …) tag each point; tools like CloudCompare, Open3D and plyfile read them.
nonisolated enum RawPLY {
    /// Text is handed out in pieces of about this many bytes, so a big file is never one big string.
    static let chunkSize = 1 << 20

    struct Layout<Point>: Sendable {
        let properties: [(type: String, name: String)]
        let comment: String
        let line: @Sendable (Point, inout String) -> Void
    }

    static let room = Layout<(world: SIMD3<Float>, rgb: SIMD3<UInt8>)>(
        properties: [("float", "x"), ("float", "y"), ("float", "z"),
                     ("uchar", "red"), ("uchar", "green"), ("uchar", "blue")],
        comment: "Skema raw export: whole LiDAR room, world metres, y up"
    ) { point, text in
        text += "\(point.world.x) \(point.world.y) \(point.world.z) \(point.rgb.x) \(point.rgb.y) \(point.rgb.z)\n"
    }

    static let kept = Layout<RawKeptPoint>(
        properties: [("float", "x"), ("float", "y"), ("float", "z"),
                     ("int", "look"), ("int", "item"), ("short", "detection")],
        comment: "Skema raw export: mask points the pipeline kept; item -1 = no sighting"
    ) { point, text in
        text += "\(point.position.x) \(point.position.y) \(point.position.z) "
        text += "\(point.look) \(point.item) \(point.detection)\n"
    }

    static let raw = Layout<RawMaskPoint>(
        properties: [("float", "x"), ("float", "y"), ("float", "z"),
                     ("int", "look"), ("int", "item"), ("short", "detection"),
                     ("uchar", "confidence"), ("float", "depth"), ("ushort", "column"), ("ushort", "row")],
        comment: "Skema raw export: every depth pixel inside each mask; item -1 = no sighting"
    ) { point, text in
        text += "\(point.position.x) \(point.position.y) \(point.position.z) "
        text += "\(point.look) \(point.item) \(point.detection) "
        text += "\(point.confidence) \(point.depth) \(point.column) \(point.row)\n"
    }

    static func header<Point>(_ layout: Layout<Point>, count: Int) -> String {
        var text = "ply\nformat ascii 1.0\ncomment \(layout.comment)\nelement vertex \(count)\n"
        for property in layout.properties {
            text += "property \(property.type) \(property.name)\n"
        }
        return text + "end_header\n"
    }

    /// The whole file in memory (small clouds, tests).
    static func data<Point>(_ points: [Point], layout: Layout<Point>) -> Data {
        var data = Data()
        encode(points, layout: layout) { data.append($0) }
        return data
    }

    /// Writes the file piece by piece.
    static func write<Point>(_ points: [Point], layout: Layout<Point>, to url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try encode(points, layout: layout) { try handle.write(contentsOf: $0) }
    }

    private static func encode<Point>(_ points: [Point], layout: Layout<Point>,
                                      emit: (Data) throws -> Void) rethrows {
        var text = header(layout, count: points.count)
        for point in points {
            layout.line(point, &text)
            if text.utf8.count >= chunkSize {
                try emit(Data(text.utf8))
                text.removeAll(keepingCapacity: true)
            }
        }
        if !text.isEmpty {
            try emit(Data(text.utf8))
        }
    }
}

/// `log.json`: pretty-printed, dates as ISO 8601, and NaN / infinity as text so a bad number never stops the export.
nonisolated enum RawJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return decoder
    }

    static func data(_ report: RawScanReport) throws -> Data {
        try encoder().encode(report)
    }
}

/// Writes one scan's raw data into a folder and zips it for the share sheet.
nonisolated enum RawDataExporter {
    static let logName = "log.json"
    static let roomName = "room.ply"
    static let keptName = "mask_kept.ply"
    static let rawName = "mask_raw.ply"
    static let depthFolder = "depth"

    /// "skema-raw-20261113-195012" (local time).
    static func folderName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "skema-raw-" + formatter.string(from: date)
    }

    /// Writes the folder and its zip under `base` (default: the app's temporary folder).
    /// - Returns: the .zip, or the folder itself when zipping fails.
    @concurrent static func export(_ log: RawScanLog, createdAt: Date,
                                   base: URL = FileManager.default.temporaryDirectory) async throws -> URL {
        let folder = base.appending(path: folderName(for: createdAt), directoryHint: .isDirectory)
        try writeFolder(log, createdAt: createdAt, at: folder)
        return (try? zip(folder)) ?? folder
    }

    static func writeFolder(_ log: RawScanLog, createdAt: Date, at folder: URL) throws {
        let files = FileManager.default
        if files.fileExists(atPath: folder.path) {
            try files.removeItem(at: folder)
        }
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        try RawJSON.data(log.report(createdAt: createdAt)).write(to: folder.appending(path: logName))
        try RawPLY.write(log.room.allPoints, layout: RawPLY.room, to: folder.appending(path: roomName))
        try RawPLY.write(log.keptPoints, layout: RawPLY.kept, to: folder.appending(path: keptName))
        try RawPLY.write(log.rawPoints, layout: RawPLY.raw, to: folder.appending(path: rawName))
        try files.createDirectory(at: folder.appending(path: depthFolder), withIntermediateDirectories: true)
        for map in log.depthMaps {
            try depthData(map.depth).write(to: folder.appending(path: map.depthFile))
            try Data(map.confidence).write(to: folder.appending(path: map.confidenceFile))
        }
    }

    /// Little-endian Float32 values, one after the other.
    static func depthData(_ depth: [Float]) -> Data {
        var data = Data(capacity: depth.count * MemoryLayout<UInt32>.size)
        for value in depth {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// Zips a folder with the system's own zipper (`NSFileCoordinator`'s `.forUploading`), next to the folder.
    static func zip(_ folder: URL) throws -> URL {
        let target = folder.deletingLastPathComponent().appending(path: folder.lastPathComponent + ".zip")
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading],
                                       error: &coordinatorError) { zipped in
            do {
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.copyItem(at: zipped, to: target)
            } catch {
                copyError = error
            }
        }
        if let error = coordinatorError ?? copyError {
            throw error
        }
        return target
    }
}
