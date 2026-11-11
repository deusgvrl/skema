import CoreGraphics
import MeasureKit

/// The color of an item's mask on the scan screen (A10-62).
nonisolated enum MaskColor: Equatable, Sendable {
    case white
    case green
}

/// One thing drawn on the scan screen: a tracked item or the subject.
nonisolated struct OverlayItem: Equatable, Sendable {
    /// "Detecting…", "Camera 1 ✓", "Subject ✓". Never a confidence %.
    let tag: String
    /// The progress ring, 0...1, while the item is pending. Nil once accepted.
    let ring: Double?
    /// The mask to draw now; nil when the item was not seen at this look.
    let mask: InstanceMask?
    let maskColor: MaskColor?
    /// Where the tag goes on the screen, pinned to the item's 3D spot. Nil when the spot is not on screen.
    let tagPosition: CGPoint?
}

/// What the scan screen shows for the tracked items (A10-62, Sketch R03 with Amadeus's 11 Nov changes).
nonisolated struct ScanOverlay: Equatable, Sendable {
    let items: [OverlayItem]
    let subject: OverlayItem?
    /// One chip per kind with accepted items, in the order Subject, Camera, Studio Lighting ("Camera • 2").
    let chips: [String]
    let canFinish: Bool

    /// - Parameters:
    ///   - masks: this look's mask for each item id (from `ObjectMap.update`'s returned ids).
    ///   - subject: the chosen subject's 3D spot, or nil.
    ///   - camera: the camera at this look; its picture is sideways (`.right`) and shown upright, filling the screen.
    init(items: [TrackedItem], masks: [Int: InstanceMask], subject: SIMD3<Float>?, camera: CameraModel,
         screenSize: CGSize) {
        func onScreen(_ spot: SIMD3<Float>) -> CGPoint? {
            Self.screenPoint(of: spot, camera: camera, screenSize: screenSize)
        }
        self.items = items.map { item in
            let isAccepted = item.status == .accepted
            let mask = item.isSeen ? masks[item.id] : nil
            return OverlayItem(
                tag: isAccepted ? Self.acceptedTag(for: item) : "Detecting…",
                ring: isAccepted ? nil : item.progress,
                mask: mask,
                maskColor: mask == nil ? nil : (isAccepted ? .green : .white),
                tagPosition: onScreen(item.position))
        }
        self.subject = subject.map {
            OverlayItem(tag: "Subject ✓", ring: nil, mask: nil, maskColor: nil, tagPosition: onScreen($0))
        }
        let accepted = items.filter { $0.status == .accepted }
        let cameras = accepted.filter { EquipmentKind(modelLabel: $0.label) == .camera }.count
        let lights = accepted.filter { EquipmentKind(modelLabel: $0.label) == .studioLighting }.count
        var chips: [String] = []
        if subject != nil { chips.append("Subject • 1") }
        if cameras > 0 { chips.append("Camera • \(cameras)") }
        if lights > 0 { chips.append("Studio Lighting • \(lights)") }
        self.chips = chips
        self.canFinish = Self.canFinish(hasSubject: subject != nil, acceptedCameras: cameras, acceptedLights: lights)
    }

    /// Finish Scan rule (Amadeus, 11 Nov): exactly one subject, at least one accepted camera
    /// and at least one accepted studio light. Pending items are not counted.
    static func canFinish(hasSubject: Bool, acceptedCameras: Int, acceptedLights: Int) -> Bool {
        if hasSubject && acceptedCameras >= 1 && acceptedLights >= 1 {
            return true
        } else {
            return false
        }
    }

    /// The full name in the app (naming rule, A10-62): "Camera 1 ✓", "Studio Lighting 2 ✓".
    private static func acceptedTag(for item: TrackedItem) -> String {
        let name = switch EquipmentKind(modelLabel: item.label) {
        case .camera: "Camera"
        case .studioLighting: "Studio Lighting"
        case nil: item.label
        }
        return item.number.map { "\(name) \($0) ✓" } ?? "\(name) ✓"
    }

    /// 3D spot → picture pixel (`DepthSampler.project`) → upright picture → screen.
    /// The sideways picture (width W, height H) is turned upright: pixel (u, v) becomes (H - v, u).
    /// The upright picture fills the screen from the centre, so its sides may be cut off.
    static func screenPoint(of spot: SIMD3<Float>, camera: CameraModel, screenSize: CGSize) -> CGPoint? {
        guard let pixel = DepthSampler.project(spot, camera: camera) else { return nil }
        let pictureHeight = CGFloat(camera.imageResolution.y)
        let upright = CGPoint(x: pictureHeight - CGFloat(pixel.y), y: CGFloat(pixel.x))
        let uprightSize = CGSize(width: pictureHeight, height: CGFloat(camera.imageResolution.x))
        let scale = max(screenSize.width / uprightSize.width, screenSize.height / uprightSize.height)
        let point = CGPoint(x: upright.x * scale + (screenSize.width - uprightSize.width * scale) / 2,
                            y: upright.y * scale + (screenSize.height - uprightSize.height * scale) / 2)
        guard point.x >= 0, point.x < screenSize.width, point.y >= 0, point.y < screenSize.height else { return nil }
        return point
    }
}
