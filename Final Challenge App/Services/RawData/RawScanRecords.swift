import CoreGraphics
import Foundation
import MeasureKit
import simd

// Raw-data export (feat/add-raw-data-logger): the records that go into `log.json`.
// This branch is a data tool for analysis only. Matrices are stored as a list of columns ([[c0], [c1], ...]),
// the same order simd uses. Positions are world metres (ARKit: y up). Times are the frames' timestamps (seconds).

/// One mask point with nothing filtered: every depth pixel inside the mask with a finite depth above 0.
nonisolated struct RawMaskPoint: Equatable, Sendable {
    let position: SIMD3<Float>
    let look: Int32
    /// The tracked item the detection's sighting joined; -1 when the detection made no sighting.
    let item: Int32
    let detection: Int16
    /// ARKit depth confidence: 0 low, 1 medium, 2 high.
    let confidence: UInt8
    /// Metres from the camera plane.
    let depth: Float
    /// The depth pixel (column, row) in the depth map.
    let column: UInt16
    let row: UInt16
}

/// One mask point the pipeline really used: `DepthSampler.worldPoints(in: mask, …)` (eroded mask, confidence 2,
/// 5 m range, 15 cm nearest-surface band). The sighting's position is the median of these points.
/// Which look, tracked item (-1: none) and detection a saved point belongs to.
nonisolated struct RawTag: Equatable, Sendable {
    let look: Int32
    let item: Int32
    let detection: Int16
}

nonisolated struct RawKeptPoint: Equatable, Sendable {
    let position: SIMD3<Float>
    let look: Int32
    let item: Int32
    let detection: Int16
}

/// The whole LiDAR depth map and confidence map of one look, kept every `RawScanLog.depthMapEvery` looks.
nonisolated struct RawDepthMap: Equatable, Sendable {
    let look: Int
    let timestamp: Double
    let camera: RawCamera
    let width: Int
    let height: Int
    /// Metres, row-major, `width * height` values.
    let depth: [Float]
    /// ARKit confidence per pixel: 0 low, 1 medium, 2 high.
    let confidence: [UInt8]

    /// File names inside the export's `depth/` folder.
    var depthFile: String { String(format: "depth/look_%06d_depth.f32", look) }
    var confidenceFile: String { String(format: "depth/look_%06d_confidence.u8", look) }
}

/// A depth map's entry in `log.json`; the numbers themselves are in the two binary files.
nonisolated struct RawDepthMapEntry: Codable, Equatable, Sendable {
    let look: Int
    let timestamp: Double
    let width: Int
    let height: Int
    /// Little-endian Float32, row-major (row 0 = top of the native picture), `width * height` values, metres.
    let depthFile: String
    /// UInt8 per pixel, same order: 0 low, 1 medium, 2 high.
    let confidenceFile: String
    /// The look's camera (also in `looks[look]`): depth pixel (column, row) sits at picture pixel
    /// ((column + 0.5) * imageWidth / width, (row + 0.5) * imageHeight / height).
    let camera: RawCamera

    init(_ map: RawDepthMap) {
        look = map.look
        timestamp = map.timestamp
        width = map.width
        height = map.height
        depthFile = map.depthFile
        confidenceFile = map.confidenceFile
        camera = map.camera
    }
}

nonisolated struct RawCamera: Codable, Equatable, Sendable {
    /// `cameraToWorld` as 4 columns of 4. Column 3 is the phone's position.
    let cameraToWorldColumns: [[Float]]
    /// The intrinsics as 3 columns of 3: fx = [0][0], fy = [1][1], cx = [2][0], cy = [2][1] (pixels).
    let intrinsicsColumns: [[Float]]
    /// Width and height of the camera picture in pixels; the intrinsics are for this size.
    let imageResolution: [Float]

    init(_ camera: CameraModel) {
        let pose = camera.cameraToWorld
        cameraToWorldColumns = [pose.columns.0, pose.columns.1, pose.columns.2, pose.columns.3].map {
            [$0.x, $0.y, $0.z, $0.w]
        }
        let lens = camera.intrinsics
        intrinsicsColumns = [lens.columns.0, lens.columns.1, lens.columns.2].map { [$0.x, $0.y, $0.z] }
        imageResolution = [camera.imageResolution.x, camera.imageResolution.y]
    }
}

nonisolated struct RawBox: Codable, Equatable, Sendable {
    /// Fractions of the native picture, top-left origin.
    let left: Double
    let top: Double
    let width: Double
    let height: Double

    init(_ box: NormalizedBox) {
        left = box.x
        top = box.y
        width = box.width
        height = box.height
    }
}

/// A mask on the depth map's grid, run-length encoded row by row: `runs` alternates 0-runs and 1-runs and
/// always starts with a 0-run (which may be 0 long). A depth pixel is 1 when its centre falls on a mask pixel.
nonisolated struct RawMaskGrid: Codable, Equatable, Sendable {
    let width: Int
    let height: Int
    let runs: [Int]
}

nonisolated struct RawSighting: Codable, Equatable, Sendable {
    let label: String
    let confidence: Float
    let position: SIMD3<Float>
    let axis: SIMD3<Float>?
    let pointCount: Int
    /// The id `ObjectMap.update` returned for this sighting.
    let itemID: Int
}

nonisolated struct RawDetection: Codable, Equatable, Sendable {
    /// Order in this look's detector output.
    let index: Int
    let kind: String
    let confidence: Float
    let maskBounds: RawBox?
    /// Size of the detector's mask (640 x 640 from YOLOE).
    let maskWidth: Int
    let maskHeight: Int
    /// The mask on the depth grid (the same mapping the depth sampler uses, no erosion).
    let depthMask: RawMaskGrid?
    /// Points inside the mask before any filter, and how many of them were saved to `mask_raw.ply`.
    let rawPointCount: Int
    let rawPointsSaved: Int
    /// Points the pipeline kept (after the 15 cm band), and how many were saved to `mask_kept.ply`.
    let keptPointCount: Int
    let keptPointsSaved: Int
    /// Nil when the detection made no sighting (no box, unknown label, or fewer than 20 kept points).
    let sighting: RawSighting?
}

nonisolated struct RawItem: Codable, Equatable, Sendable {
    let id: Int
    let label: String
    let status: String
    let number: Int?
    let position: SIMD3<Float>
    let progress: Double
    let isSeen: Bool

    init(_ item: TrackedItem) {
        id = item.id
        label = item.label
        status = item.status == .accepted ? "accepted" : "pending"
        number = item.number
        position = item.position
        progress = item.progress
        isSeen = item.isSeen
    }
}

nonisolated struct RawLook: Codable, Equatable, Sendable {
    /// 0, 1, 2 … in order. The `look` property in the .ply files is this number.
    let index: Int
    let timestamp: Double
    let camera: RawCamera
    let depthWidth: Int?
    let depthHeight: Int?
    let detections: [RawDetection]
    /// Every tracked item after `ObjectMap.update`.
    let items: [RawItem]
    /// Room points this look added to `room.ply` (0 when the room was not sampled at this look).
    let roomPointsAdded: Int
}

nonisolated struct RawSubjectTap: Codable, Equatable, Sendable {
    let timestamp: Double
    let screenTap: [Double]
    let screenSize: [Double]
    /// The tap in native picture pixels; nil when the tap was off the picture.
    let picturePoint: [Double]?
    let succeeded: Bool
    /// The subject's spot from the tap patch; nil when it failed.
    let position: SIMD3<Float>?
}

extension RawSubjectTap {
    init(tap: CGPoint, screenSize: CGSize, camera: CameraModel, at time: Double, centre: SIMD3<Float>?) {
        let picture = ScanOverlay.picturePoint(fromScreen: tap, camera: camera, screenSize: screenSize)
        self.init(timestamp: time, screenTap: [tap.x, tap.y], screenSize: [screenSize.width, screenSize.height],
                  picturePoint: picture.map { [$0.x, $0.y] }, succeeded: centre != nil, position: centre)
    }
}

nonisolated struct RawSubjectMask: Codable, Equatable, Sendable {
    let timestamp: Double
    let pointCount: Int
    let position: SIMD3<Float>?
}

nonisolated struct RawMeasuredItem: Codable, Equatable, Sendable {
    let trackerID: Int?
    let equipmentID: String
    let name: String
    let status: String?
    let distanceToSubject: Float?
    let height: Float?
    let floorOffset: SIMD2<Float>?
    let pointCount: Int?
    /// What was written onto the draft equipment (metres as text, plan points).
    let writtenDistance: String
    let writtenHeight: String
    let writtenPosition: [Double]
}

nonisolated struct RawFinish: Codable, Equatable, Sendable {
    let lastLookTimestamp: Double?
    let floorY: Float?
    let subject: SIMD3<Float>?
    let items: [RawMeasuredItem]
}

/// The numbers the pipeline used, so the analysis can replay it.
nonisolated struct RawSettings: Codable, Equatable, Sendable {
    var lookInterval = EquipmentTracker.lookInterval
    var mergeRadius = ObjectMap.mergeRadius
    var acceptAfter = ObjectMap.acceptAfter
    var maxGap = ObjectMap.maxGap
    var maxRange = DepthSampler.maxRange
    var depthBand: Float = 0.15
    var maskErosion = 1
    var minConfidence = 2
    var minSightingPoints = 20
}

/// The memory caps of this recording (see `RawScanLog`).
nonisolated struct RawCaps: Codable, Equatable, Sendable {
    let maxLooks: Int
    let maxPointsPerDetection: Int
    let maxRawPoints: Int
    let maxKeptPoints: Int
    let roomVoxelSize: Float
    let roomMaxPoints: Int
    let roomInterval: Double
    let roomPixelStride: Int
    let depthMapEvery: Int
    let maxDepthMaps: Int
}

nonisolated struct RawCounts: Codable, Equatable, Sendable {
    let looks: Int
    /// Looks after `maxLooks`, not recorded.
    let droppedLooks: Int
    let rawPoints: Int
    let keptPoints: Int
    let roomPoints: Int
    let depthMaps: Int
    /// True when a budget ran out, so later looks have counts but no saved points.
    let pointBudgetReached: Bool
}

/// `log.json`.
nonisolated struct RawScanReport: Codable, Equatable, Sendable {
    var formatVersion = 1
    let createdAt: Date
    var files = [
        "room.ply": "whole LiDAR room, 1 cm voxels: x y z red green blue",
        "mask_kept.ply": "points the pipeline kept per detection: x y z look item detection",
        "mask_raw.ply": "every depth pixel inside each mask: x y z look item detection confidence depth column row",
        "depth/": "whole depth map (Float32 metres) + confidence map (UInt8) of every 10th look; see depthMaps"
    ]
    var settings = RawSettings()
    let caps: RawCaps
    let counts: RawCounts
    let looks: [RawLook]
    let subjectTaps: [RawSubjectTap]
    let subjectMasks: [RawSubjectMask]
    let depthMaps: [RawDepthMapEntry]
    let finish: RawFinish?
}
