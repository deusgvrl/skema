import Foundation
import MeasureKit

/// Everything one scan records for the raw-data export, kept in memory with fixed caps so a long scan stays small:
/// - at most `maxLooks` looks (5 minutes at 10 looks a second); later looks are only counted;
/// - each detection saves at most `RawLookSampler.maxPointsPerDetection` raw and kept points (evenly thinned);
/// - once `maxRawPoints` or `maxKeptPoints` is reached, later looks keep their counts but save no points;
/// - the room is sampled every `roomInterval` seconds into a `ScanCloud` (1 cm voxels, at most 600,000 points);
/// - every `depthMapEvery`-th look keeps its whole depth and confidence maps, at most `maxDepthMaps` of them
///   (256 x 192 on iPhone: about 240 KB each, so at most about 36 MB).
nonisolated struct RawScanLog: Sendable {
    static let maxLooks = 3000
    static let maxRawPoints = 1_000_000
    static let maxKeptPoints = 1_000_000
    static let roomInterval = 0.5
    static let depthMapEvery = 10
    static let maxDepthMaps = 150

    private(set) var looks: [RawLook] = []
    private(set) var droppedLooks = 0
    private(set) var rawPoints: [RawMaskPoint] = []
    private(set) var keptPoints: [RawKeptPoint] = []
    private(set) var room = ScanCloud()
    private(set) var subjectTaps: [RawSubjectTap] = []
    private(set) var subjectMasks: [RawSubjectMask] = []
    private(set) var finish: RawFinish?
    private(set) var depthMaps: [RawDepthMap] = []
    private var lastRoomTime: Double?

    /// The index the next recorded look gets.
    var nextLook: Int { looks.count }

    var wantsLook: Bool { looks.count < Self.maxLooks }

    /// False once either point budget is used up.
    var savesPoints: Bool {
        rawPoints.count < Self.maxRawPoints && keptPoints.count < Self.maxKeptPoints
    }

    func wantsRoom(at time: Double) -> Bool {
        guard let lastRoomTime else { return true }
        return time - lastRoomTime >= Self.roomInterval - EquipmentTracker.tolerance
    }

    mutating func dropLook() {
        droppedLooks += 1
    }

    /// What to sample for the tracker's latest look. Nil (and the look only counted) once `maxLooks` is reached.
    mutating func request(for found: [EquipmentDetection], tracker: EquipmentTracker,
                          frame: ScanFrame) -> RawLookSampler.Request? {
        guard wantsLook else {
            dropLook()
            return nil
        }
        return RawLookSampler.Request(
            detections: found, sightings: tracker.latestSightings, joinedIDs: tracker.latestJoinedIDs,
            items: tracker.items, frame: frame, look: nextLook, savesPoints: savesPoints,
            samplesRoom: wantsRoom(at: frame.timestamp))
    }

    /// Adds a sampled look (from `request(for:tracker:frame:)`).
    mutating func append(_ sample: RawLookSample, for request: RawLookSampler.Request) {
        append(sample, at: request.frame.timestamp, camera: request.frame.camera, depth: request.frame.depth,
               items: request.items)
    }

    mutating func append(_ sample: RawLookSample, at time: Double, camera: CameraModel, depth: DepthFrame?,
                         items: [TrackedItem]) {
        guard wantsLook else {
            dropLook()
            return
        }
        var roomAdded = 0
        if sample.sampledRoom {
            lastRoomTime = time
            roomAdded = room.add(sample.roomPoints).count
        }
        rawPoints += sample.rawPoints
        keptPoints += sample.keptPoints
        if let depth, looks.count.isMultiple(of: Self.depthMapEvery), depthMaps.count < Self.maxDepthMaps {
            depthMaps.append(RawDepthMap(look: looks.count, timestamp: time, camera: RawCamera(camera),
                                         width: depth.width, height: depth.height,
                                         depth: depth.depth, confidence: depth.confidence))
        }
        looks.append(RawLook(index: looks.count, timestamp: time, camera: RawCamera(camera),
                             depthWidth: depth?.width, depthHeight: depth?.height,
                             detections: sample.detections, items: items.map(RawItem.init),
                             roomPointsAdded: roomAdded))
    }

    mutating func addSubjectTap(_ tap: RawSubjectTap) {
        subjectTaps.append(tap)
    }

    mutating func addSubjectMask(_ mask: RawSubjectMask) {
        subjectMasks.append(mask)
    }

    mutating func setFinish(_ finish: RawFinish) {
        self.finish = finish
    }

    var caps: RawCaps {
        RawCaps(maxLooks: Self.maxLooks, maxPointsPerDetection: RawLookSampler.maxPointsPerDetection,
                maxRawPoints: Self.maxRawPoints, maxKeptPoints: Self.maxKeptPoints,
                roomVoxelSize: ScanCloud.voxelSize, roomMaxPoints: ScanCloud.maxPoints,
                roomInterval: Self.roomInterval, roomPixelStride: RawLookSampler.roomPixelStride,
                depthMapEvery: Self.depthMapEvery, maxDepthMaps: Self.maxDepthMaps)
    }

    /// `log.json`'s content.
    func report(createdAt: Date) -> RawScanReport {
        let counts = RawCounts(looks: looks.count, droppedLooks: droppedLooks, rawPoints: rawPoints.count,
                               keptPoints: keptPoints.count, roomPoints: room.count, depthMaps: depthMaps.count,
                               pointBudgetReached: !savesPoints)
        return RawScanReport(createdAt: createdAt, caps: caps, counts: counts, looks: looks,
                             subjectTaps: subjectTaps, subjectMasks: subjectMasks,
                             depthMaps: depthMaps.map(RawDepthMapEntry.init), finish: finish)
    }
}

extension RawFinish {
    /// The finish as `ScanViewModel.finishTapped` left it: each draft equipment's measurement and written values,
    /// plus the subject's own measurement.
    @MainActor
    init(results: [UUID: EquipmentResult], subjectID: UUID, equipmentIDs: [Int: UUID], nodes: [Equipment],
         lastLook: Double?, floorY: Float?, subject: SIMD3<Float>?) {
        let trackerIDs = Dictionary(equipmentIDs.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
        var items = nodes.map { equipment in
            let result = results[equipment.id]
            return RawMeasuredItem(
                trackerID: trackerIDs[equipment.id], equipmentID: equipment.id.uuidString, name: equipment.name,
                status: result?.status.rawValue, distanceToSubject: result?.distanceToSubject,
                height: result?.height, floorOffset: result?.floorOffset, pointCount: result?.pointCount,
                writtenDistance: equipment.distance, writtenHeight: equipment.height,
                writtenPosition: [equipment.position.x, equipment.position.y])
        }
        if let result = results[subjectID] {
            items.append(RawMeasuredItem(
                trackerID: nil, equipmentID: subjectID.uuidString, name: "subject", status: result.status.rawValue,
                distanceToSubject: nil, height: result.height, floorOffset: nil, pointCount: result.pointCount,
                writtenDistance: "", writtenHeight: "", writtenPosition: []))
        }
        self.init(lastLookTimestamp: lastLook, floorY: floorY, subject: subject, items: items)
    }
}
