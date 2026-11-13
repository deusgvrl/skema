import Foundation
import MeasureKit
import simd
import Testing
@testable import Final_Challenge_App

@Suite("Raw-data export writers")
struct RawDataExportTests {
    private let camera = CameraModel(intrinsics: matrix_identity_float3x3, imageResolution: SIMD2(2, 2),
                                     cameraToWorld: matrix_identity_float4x4)

    @Test("A kept-points PLY has the header and one tagged line per point")
    func keptPLY() throws {
        let points = [RawKeptPoint(position: SIMD3(1, 2.5, -3), look: 4, item: -1, detection: 2)]

        let text = try #require(String(data: RawPLY.data(points, layout: RawPLY.kept), encoding: .utf8))

        #expect(text == """
            ply
            format ascii 1.0
            comment Skema raw export: mask points the pipeline kept; item -1 = no sighting
            element vertex 1
            property float x
            property float y
            property float z
            property int look
            property int item
            property short detection
            end_header
            1.0 2.5 -3.0 4 -1 2

            """)
    }

    @Test("A room PLY line is x y z red green blue")
    func roomPLY() throws {
        let points = [(world: SIMD3<Float>(0.5, 0, 1), rgb: SIMD3<UInt8>(255, 0, 7))]

        let text = try #require(String(data: RawPLY.data(points, layout: RawPLY.room), encoding: .utf8))

        #expect(text.contains("element vertex 1\n"))
        #expect(text.hasSuffix("end_header\n0.5 0.0 1.0 255 0 7\n"))
    }

    @Test("A raw-points PLY lists all ten properties and every point")
    func rawPLY() throws {
        let point = RawMaskPoint(position: SIMD3(0, 0, -1), look: 0, item: 3, detection: 1,
                                 confidence: 1, depth: 1, column: 10, row: 20)

        let text = try #require(String(data: RawPLY.data([point, point], layout: RawPLY.raw), encoding: .utf8))

        #expect(text.contains("element vertex 2\n"))
        #expect(text.components(separatedBy: "\n").filter { $0.hasPrefix("property ") }.count == 10)
        #expect(text.hasSuffix("end_header\n0.0 0.0 -1.0 0 3 1 1 1.0 10 20\n0.0 0.0 -1.0 0 3 1 1 1.0 10 20\n"))
    }

    @Test("log.json decodes back to the same report")
    func jsonRoundTrip() throws {
        var log = RawScanLog()
        let sample = RawLookSample(detections: [], rawPoints: [], keptPoints: [], roomPoints: [], sampledRoom: false)
        log.append(sample, at: 1.5, camera: camera, depth: nil, items: [
            TrackedItem(id: 0, label: "studio lighting", status: .pending, number: nil, position: SIMD3(1, 2, 3),
                        progress: 0.5, isSeen: true)
        ])
        log.addSubjectTap(RawSubjectTap(timestamp: 1.5, screenTap: [10, 20], screenSize: [100, 200],
                                        picturePoint: nil, succeeded: false, position: nil))
        let report = log.report(createdAt: Date(timeIntervalSince1970: 1_000_000))

        let data = try RawJSON.data(report)
        let decoded = try RawJSON.decoder().decode(RawScanReport.self, from: data)

        #expect(decoded == report)
        #expect(decoded.looks.first?.camera.cameraToWorldColumns.count == 4)
        #expect(decoded.looks.first?.items.first?.status == "pending")
    }

    @Test("A NaN in the log is written as text instead of failing the export")
    func jsonNaN() throws {
        var log = RawScanLog()
        log.addSubjectMask(RawSubjectMask(timestamp: 0, pointCount: 0, position: SIMD3(.nan, 0, 0)))

        let text = try #require(String(data: RawJSON.data(log.report(createdAt: .now)), encoding: .utf8))

        #expect(text.contains("\"nan\""))
    }

    @Test("Mask points keep every in-mask pixel with depth, and the depth mask is run-length encoded")
    func maskPoints() {
        let mask = InstanceMask(width: 2, height: 2, pixels: [1, 1, 0, 0])
        let depth = DepthFrame(width: 2, height: 2, depth: [2, .nan, 1, 1], confidence: [0, 2, 2, 2])

        let result = RawLookSampler.maskPoints(in: mask, depth: depth, camera: camera,
                                               tag: RawTag(look: 7, item: 1, detection: 0))

        #expect(result.points.count == 1)
        #expect(result.points.first?.depth == 2)
        #expect(result.points.first?.confidence == 0)
        #expect(result.points.first?.look == 7)
        #expect(result.grid == RawMaskGrid(width: 2, height: 2, runs: [0, 2, 2]))
    }

    @Test("Thinning keeps at most the limit, spread evenly from the first value")
    func thinning() {
        #expect(RawLookSampler.thinned(Array(0..<10), to: 4) == [0, 2, 5, 7])
        #expect(RawLookSampler.thinned([1, 2], to: 4) == [1, 2])
    }

    @Test("A detection without a sighting gets none; the next one gets its item id")
    func matching() {
        let first = InstanceMask(width: 1, height: 1, pixels: [1])
        let second = InstanceMask(width: 2, height: 1, pixels: [1, 1])
        let detections = [EquipmentDetection(kind: .studioLighting, confidence: 0.5, mask: first),
                          EquipmentDetection(kind: .camera, confidence: 0.9, mask: second)]
        let sighting = Sighting(label: "camera", confidence: 0.9, position: .zero, axis: nil, pointCount: 30)

        let matches = RawLookSampler.matchSightings(
            detections, sightings: [SightedDetection(sighting: sighting, mask: second)], joinedIDs: [5])

        #expect(matches.count == 2)
        #expect(matches[0] == nil)
        #expect(matches[1]?.itemID == 5)
    }

    @Test("The export folder holds log.json and the three PLY files")
    func folder() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "raw-export-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }

        try RawDataExporter.writeFolder(RawScanLog(), createdAt: .now, at: folder)

        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names == ["depth", "log.json", "mask_kept.ply", "mask_raw.ply", "room.ply"])
    }

    @Test("Every 10th look keeps its whole depth and confidence maps, written as binary files")
    func depthMaps() throws {
        var log = RawScanLog()
        let depth = DepthFrame(width: 2, height: 1, depth: [1.5, .nan], confidence: [0, 2])
        let sample = RawLookSample(detections: [], rawPoints: [], keptPoints: [], roomPoints: [], sampledRoom: false)
        for look in 0...10 {
            log.append(sample, at: Double(look), camera: camera, depth: depth, items: [])
        }
        let folder = FileManager.default.temporaryDirectory.appending(path: "raw-depth-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }

        try RawDataExporter.writeFolder(log, createdAt: .now, at: folder)

        #expect(log.depthMaps.map(\.look) == [0, 10])
        let first = try #require(log.report(createdAt: .now).depthMaps.first)
        #expect(first.depthFile == "depth/look_000000_depth.f32")
        let depthBytes = try Data(contentsOf: folder.appending(path: first.depthFile))
        #expect(depthBytes.count == 8)
        #expect(depthBytes.prefix(4) == Data([0x00, 0x00, 0xC0, 0x3F]))
        #expect(try Data(contentsOf: folder.appending(path: first.confidenceFile)) == Data([0, 2]))
    }

    @Test("The export folder is zipped next to itself")
    func zipped() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "raw-zip-test-\(UUID().uuidString)")
        try RawDataExporter.writeFolder(RawScanLog(), createdAt: .now, at: folder)
        defer { try? FileManager.default.removeItem(at: folder) }

        let zip = try RawDataExporter.zip(folder)
        defer { try? FileManager.default.removeItem(at: zip) }

        #expect(zip.lastPathComponent == folder.lastPathComponent + ".zip")
        #expect(try Data(contentsOf: zip).prefix(2) == Data("PK".utf8))
    }
}
