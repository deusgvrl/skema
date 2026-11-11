#if DEBUG
import Foundation
import MeasureKit
import os
import simd

/// What the measure debug screen shows, copied out of the engine so the screen never touches the engine's state.
nonisolated struct MeasureDebugSnapshot: Sendable {
    var floorY: Float?
    var planeCount = 0
    var tracking = ScanTracking.notAvailable
    var results: [UUID: EquipmentResult] = [:]
    var centres: [UUID: EquipmentCentres] = [:]
    var anchors: [UUID: [SIMD3<Float>]] = [:]
    /// Share of the latest depth map (0 to 1) that has a reading at all, and the share that is high confidence.
    var depthValidShare: Float?
    var depthHighShare: Float?
    /// For each item whose base was not seen: its top centre found with the "base must touch the floor" rule skipped.
    /// A data-gathering aid to compare "height from the top only" with a tape measure, not a measurement rule.
    var topsWithoutBase: [UUID: SIMD3<Float>] = [:]
}

/// The answer to a tap: the anchor's world point when there was a usable depth reading, and a message in plain words.
nonisolated struct MeasureDebugTap: Sendable {
    var world: SIMD3<Float>?
    var message: String
}

/// Looks at the depth map around a tapped pixel, to find the nearest usable reading or to say why there is none.
nonisolated enum MeasureDebugDepthProbe {
    /// How far from the tapped pixel (in depth pixels) a usable reading is looked for.
    static let searchRadius = 5
    /// Medium confidence is enough for the starting point of an item. The points that are measured still need high.
    static let minSeedConfidence: UInt8 = 1
    static let highConfidence: UInt8 = 2

    struct Pixel {
        var column: Int
        var row: Int
        var pixelsAway: Float
        var confidence: UInt8
        var depth: Float

        /// Closer to the tap wins; for the same distance the higher confidence wins.
        func isBetter(than other: Pixel) -> Bool {
            pixelsAway < other.pixelsAway || (pixelsAway == other.pixelsAway && confidence > other.confidence)
        }
    }

    /// The usable depth pixel nearest to (column, row), or nil when none is within `searchRadius`.
    static func nearestUsablePixel(in depth: DepthFrame, column: Int, row: Int) -> Pixel? {
        var best: Pixel?
        for rowOffset in -searchRadius...searchRadius {
            for columnOffset in -searchRadius...searchRadius {
                guard let reading = reading(in: depth, column: column + columnOffset, row: row + rowOffset),
                      reading.confidence >= minSeedConfidence else { continue }
                let candidate = Pixel(
                    column: column + columnOffset, row: row + rowOffset,
                    pixelsAway: hypot(Float(columnOffset), Float(rowOffset)),
                    confidence: reading.confidence, depth: reading.depth
                )
                if let current = best, !candidate.isBetter(than: current) { continue }
                best = candidate
            }
        }
        return best
    }

    /// Why there is no usable reading at the tap: what the tapped pixel and the area around it contain.
    static func noDepthMessage(in depth: DepthFrame, column: Int, row: Int) -> String {
        let tapped = reading(in: depth, column: column, row: row)
        let tappedText = tapped.map { String(format: "%.2f m, %@ confidence", $0.depth, level($0.confidence)) }
            ?? "no reading"
        var valid = 0, high = 0, medium = 0
        for rowOffset in -searchRadius...searchRadius {
            for columnOffset in -searchRadius...searchRadius {
                let neighbour = reading(in: depth, column: column + columnOffset, row: row + rowOffset)
                guard let found = neighbour else { continue }
                valid += 1
                if found.confidence >= highConfidence {
                    high += 1
                } else if found.confidence >= minSeedConfidence {
                    medium += 1
                }
            }
        }
        let side = 2 * searchRadius + 1
        return "No usable depth at the tap. The tapped pixel: \(tappedText). "
            + "In the \(side) by \(side) pixels around it: \(valid) have a reading, \(high) high, \(medium) medium. "
            + "Dark, shiny or very close surfaces often give no reading."
    }

    /// The share of the depth map that has a reading, and the share that is high confidence (0 to 1).
    static func coverage(of depth: DepthFrame) -> (valid: Float, high: Float) {
        var valid = 0, high = 0
        for index in depth.depth.indices {
            let value = depth.depth[index]
            guard value.isFinite, value > 0 else { continue }
            valid += 1
            if depth.confidence[index] >= highConfidence { high += 1 }
        }
        let total = Float(max(1, depth.depth.count))
        return (Float(valid) / total, Float(high) / total)
    }

    static func level(_ confidence: UInt8) -> String {
        switch confidence {
        case 0: "low"
        case 1: "medium"
        default: "high"
        }
    }

    /// The depth and confidence at (column, row) when the pixel is inside the map and has a reading at all.
    private static func reading(in depth: DepthFrame, column: Int, row: Int) -> (depth: Float, confidence: UInt8)? {
        guard (0..<depth.width).contains(column), (0..<depth.height).contains(row) else { return nil }
        let index = row * depth.width + column
        let value = depth.depth[index]
        guard value.isFinite, value > 0 else { return nil }
        return (value, depth.confidence[index])
    }
}

/// Does the measure debug screen's per-frame work off the main thread (A10-41).
///
/// An item is "painted" by tapping: each tap becomes an anchor (a spot in the room), and every frame the depth pixels
/// in a vertical column of `radius` around each of the item's anchors, from just above the floor up, are added to it.
/// This is a temporary stand-in for the real detector's regions (A10-5); everything after that (centres, distance,
/// height, status) is the real measurement code.
actor MeasureDebugEngine {
    /// Items leave out the floor and its noise: their points must be at least this far above the floor plane.
    private static let floorMargin: Float = 0.03
    /// The highest an item can be above the floor.
    private static let maxItemHeight: Float = 3.0

    private let logger = Logger(subsystem: "com.skema.adac5a10", category: "MeasureDebug")
    private var measurements = ScanMeasurements()
    private var anchors: [UUID: [SIMD3<Float>]] = [:]
    private var subject: UUID?
    private var radius: Float = 0.1
    private var latestDepth: DepthFrame?
    private var latestCamera: CameraModel?
    private var planes: [ScanPlane] = []
    private var tracking = ScanTracking.notAvailable
    private var loggedPlanes: [UUID: (floorY: Float, isFloor: Bool)] = [:]
    /// The item of every tap, in order, so the last tap can be undone.
    private var tapHistory: [UUID] = []

    func setSubject(_ id: UUID?) {
        subject = id
    }

    func setRadius(_ metres: Float) {
        radius = metres
    }

    /// Forgets every painted item and every point. The planes stay, because the room has not changed.
    func reset() {
        measurements = ScanMeasurements()
        anchors = [:]
        tapHistory = []
    }

    /// Takes back the last tap: forgets its anchor and the points of that item, which are collected again from the
    /// item's remaining anchors in the next frames. Other items keep their points. False when there is nothing to undo.
    func undoLastTap() -> Bool {
        guard let item = tapHistory.popLast() else { return false }
        anchors[item]?.removeLast()
        if anchors[item]?.isEmpty == true { anchors[item] = nil }
        measurements.remove(item)
        return true
    }

    /// Takes one frame: remembers the planes and adds the painted items' points while tracking is normal.
    func ingest(_ frame: ScanFrame) {
        tracking = frame.tracking
        planes = frame.planes
        logChangedPlanes(frame.planes)
        // Frames with poor tracking can have shifted coordinates, and frames without depth have nothing to add.
        guard frame.tracking == .normal, let depth = frame.depth else { return }
        latestDepth = depth
        latestCamera = frame.camera
        // Items are columns above the floor, so nothing is added until a floor is known.
        guard let floorY = FloorPicker.floorY(frame.planes.map(\.horizontalPlane)) else { return }
        let heights = (floorY + Self.floorMargin)...(floorY + Self.maxItemHeight)
        let wholeImage = NormalizedBox(x: 0, y: 0, width: 1, height: 1)
        for (item, points) in anchors {
            let mask = DepthSampler.mask(
                inColumnsAround: points, radius: radius, betweenY: heights, depth: depth, camera: frame.camera
            )
            // The columns already bound each item, so the nearest-surface band is switched off.
            measurements.add(
                to: item, box: wholeImage, mask: mask, depth: depth, camera: frame.camera, depthBand: .infinity
            )
        }
    }

    /// The world point under a tapped point of the native camera image (0 to 1 in both directions, top-left origin),
    /// worked out from the nearest usable depth reading (see `MeasureDebugDepthProbe`). It becomes an anchor of `item`.
    /// The anchor only places the item: the points that are measured still need high confidence.
    func addAnchor(atImagePoint point: SIMD2<Float>, to item: UUID) -> MeasureDebugTap {
        guard let depth = latestDepth, let camera = latestCamera else {
            let message = "No depth yet: wait until tracking is normal and the floor shows."
            return MeasureDebugTap(world: nil, message: message)
        }
        let column = min(depth.width - 1, max(0, Int(point.x * Float(depth.width))))
        let row = min(depth.height - 1, max(0, Int(point.y * Float(depth.height))))
        guard let pixel = MeasureDebugDepthProbe.nearestUsablePixel(in: depth, column: column, row: row) else {
            let message = MeasureDebugDepthProbe.noDepthMessage(in: depth, column: column, row: row)
            return MeasureDebugTap(world: nil, message: message)
        }
        // The pixel's own position in the camera image: more exact than the tapped point.
        let imagePixel = SIMD2(
            (Float(pixel.column) + 0.5) * camera.imageResolution.x / Float(depth.width),
            (Float(pixel.row) + 0.5) * camera.imageResolution.y / Float(depth.height)
        )
        let world = DepthSampler.unproject(pixel: imagePixel, depth: pixel.depth, camera: camera)
        anchors[item, default: []].append(world)
        tapHistory.append(item)
        let message = String(
            format: "Anchor set: %.2f m away, %@ confidence, %.0f pixels from the tap.",
            pixel.depth, MeasureDebugDepthProbe.level(pixel.confidence), pixel.pixelsAway
        )
        return MeasureDebugTap(world: world, message: message)
    }

    func snapshot() -> MeasureDebugSnapshot {
        let floorY = FloorPicker.floorY(planes.map(\.horizontalPlane))
        var snapshot = MeasureDebugSnapshot(
            floorY: floorY, planeCount: planes.count, tracking: tracking, anchors: anchors
        )
        if let depth = latestDepth {
            let coverage = MeasureDebugDepthProbe.coverage(of: depth)
            snapshot.depthValidShare = coverage.valid
            snapshot.depthHighShare = coverage.high
        }
        // Results need a floor. Without a subject there are no distances (an unknown id never matches an item).
        if let floorY {
            let subjectID = subject ?? UUID()
            snapshot.results = measurements.results(subject: subjectID, floorY: floorY)
            snapshot.centres = measurements.centres(subject: subjectID, floorY: floorY)
            snapshot.topsWithoutBase = topCentresWithoutBase(floorY: floorY, centres: snapshot.centres)
        }
        return snapshot
    }

    /// The top centre of each item whose base was not seen. With the item itself as the "subject", only the rule that
    /// a base must touch the floor is skipped: too few points still gives no centre.
    private func topCentresWithoutBase(floorY: Float, centres: [UUID: EquipmentCentres]) -> [UUID: SIMD3<Float>] {
        var tops: [UUID: SIMD3<Float>] = [:]
        for (item, own) in centres where own.status == .baseNotSeen {
            if let top = measurements.centres(subject: item, floorY: floorY)[item]?.topCentre {
                tops[item] = top
            }
        }
        return tops
    }

    /// Writes every plane ARKit reports to the log when it is new or changed, so the floor choice can be checked.
    private func logChangedPlanes(_ planes: [ScanPlane]) {
        for plane in planes {
            if let known = loggedPlanes[plane.id],
               abs(known.floorY - plane.worldY) < 0.01, known.isFloor == plane.isFloor {
                continue
            }
            loggedPlanes[plane.id] = (plane.worldY, plane.isFloor)
            let name = String(plane.id.uuidString.prefix(8))
            logger.info("plane \(name) y=\(plane.worldY) isFloor=\(plane.isFloor) area=\(plane.area)")
        }
    }
}
#endif
