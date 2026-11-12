import CoreGraphics
import MeasureKit

/// One scan's tracking (A10-62): each look's detections → 3D sightings → `ObjectMap` → what the overlay shows.
nonisolated struct EquipmentTracker: Sendable {
    /// YOLOE looks at most 10 times a second (Amadeus, 12 Nov). The LiDAR points keep the session's 15.
    static let lookInterval: Double = 0.1
    /// Rounding room: 0.3 - 0.2 is 0.0999…, not exactly 0.1.
    static let tolerance: Double = 1e-6

    private var map = ObjectMap()
    private var masks: [Int: InstanceMask] = [:]
    /// The camera at the latest look; nil before the first one.
    private(set) var camera: CameraModel?
    private var lastLook: Double?
    /// Ids of accepted items already handed out by `look`, so each is added to the setup once.
    private var handedOut: Set<Int> = []

    /// True when at least `lookInterval` has passed since the last look (or there was none).
    func wantsLook(at time: Double) -> Bool {
        guard let lastLook else { return true }
        return time - lastLook >= Self.lookInterval - Self.tolerance
    }

    /// One look of the detector at `time`. A failed look or a frame without depth is `[]`: nothing seen,
    /// so a pending item's clock pauses for it (`ObjectMap.update`).
    /// Returns the items that are accepted now and were never returned before.
    mutating func look(_ detections: [EquipmentDetection], depth: DepthFrame?, camera: CameraModel,
                       at time: Double) -> [TrackedItem] {
        lastLook = time
        self.camera = camera
        let sighted = EquipmentSightings.make(from: detections, depth: depth, camera: camera)
        let ids = map.update(sighted.map(\.sighting), at: time)
        masks = Dictionary(zip(ids, sighted.map(\.mask)), uniquingKeysWith: { first, _ in first })
        return newlyAccepted(map.items)
    }

    /// What the scan screen shows now. Nil before the first look (no camera yet).
    func overlay(subject: SIMD3<Float>?, screenSize: CGSize) -> ScanOverlay? {
        guard let camera else { return nil }
        return ScanOverlay(items: map.items, masks: masks, subject: subject, camera: camera, screenSize: screenSize)
    }

    /// The accepted items in `items` that were not returned before, in `items`' order; remembers them in `handedOut`.
    private mutating func newlyAccepted(_ items: [TrackedItem]) -> [TrackedItem] {
        let fresh = items.filter { item in
            item.status == .accepted && !handedOut.contains(item.id)
        }
        for item in fresh {
            handedOut.insert(item.id)
        }
        return fresh
    }
}
