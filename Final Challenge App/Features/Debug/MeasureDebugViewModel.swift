#if DEBUG
import ARKit
import Foundation
import MeasureKit
import Observation
import RealityKit
import UIKit

/// One line of the results list on the measure debug screen.
struct MeasureDebugRow: Identifiable {
    let id: UUID
    let text: String
}

/// State and actions for the measure debug screen (A10-41): runs the scan on an `ARView`'s own session,
/// turns taps into painted items and shows what the measurement code finds. Debug builds only.
@Observable
final class MeasureDebugViewModel {
    enum Target: String, CaseIterable {
        case subject = "Subject"
        case item = "Item"
    }

    /// The tap is more than this far from ARKit's raycast hit when something is wrong with the axes or the orientation.
    private static let validationLimitMetres: Float = 0.05

    var target = Target.subject
    var radiusCentimetres = 10.0
    var statusText = "Scan: starting"
    var floorText = "Floor: not found yet. Move the iPhone over the floor."
    var depthText = "Depth: no frame yet"
    var validationText = "Tap something: the depth is compared with ARKit's raycast."
    var rows: [MeasureDebugRow] = []
    /// The Detector switch (A10-60's model finds the items) and the depth band switch for the detector's items.
    var detectorEnabled = false
    var bandOn = false

    let arView: ARView
    let detector: MeasureDebugDetectorLoop
    @ObservationIgnored private let scan: ScanSession
    @ObservationIgnored private let engine: MeasureDebugEngine
    @ObservationIgnored private var appliedVersion = 0
    @ObservationIgnored private let subjectID = UUID()
    @ObservationIgnored private var itemIDs: [UUID] = []
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var markers: [AnchorEntity] = []

    init() {
        // `ScanSession` runs this session. The view only draws the camera, so it must not configure the session itself.
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView = view
        // The view's default visual effects cost a lot of power and this screen has no use for them.
        arView.renderOptions.insert([
            .disableMotionBlur, .disableDepthOfField, .disableGroundingShadows,
            .disableCameraGrain, .disableHDR, .disablePersonOcclusion, .disableFaceMesh
        ])
        // Five frames a second are plenty for items that do not move, and a third of the work of fifteen.
        scan = ScanSession(session: arView.session, frameInterval: 1.0 / 5.0)
        let engine = MeasureDebugEngine()
        self.engine = engine
        detector = MeasureDebugDetectorLoop(engine: engine) { [weak view] in Self.displayTransform(of: view) }
    }

    // MARK: - Scan

    func start() {
        guard scan.isLiDARSupported else {
            statusText = "Scan: this iPhone has no LiDAR"
            return
        }
        // Listen before starting, because a stream does not replay frames it missed.
        let frames = scan.frames()
        let states = scan.states()
        do {
            try scan.start()
        } catch {
            statusText = "Scan: \(error)"
            return
        }
        tasks = [
            Task.detached { [engine, subjectID] in
                await engine.setSubject(subjectID)
                for await frame in frames {
                    await engine.ingest(frame)
                }
            },
            Task { [weak self] in
                for await state in states {
                    self?.statusText = "Scan: \(state)"
                }
            },
            Task { [weak self] in
                await self?.pollSnapshots()
            }
        ]
    }

    func stop() {
        detector.stop()
        scan.stop()
        tasks.forEach { $0.cancel() }
        tasks = []
        removeMarkers()
    }

    // MARK: - Painting items

    func tapped(at point: CGPoint) {
        guard let imagePoint = imagePoint(forViewPoint: point) else {
            validationText = "That tap could not be placed on the camera image (no frame yet, or outside the picture)."
            return
        }
        let item = targetID()
        let raycastWorld = raycastPosition(at: point)
        Task {
            let tap = await engine.addAnchor(atImagePoint: imagePoint, to: item)
            guard let world = tap.world else {
                validationText = tap.message
                return
            }
            validationText = tap.message + " " + Self.validation(depthWorld: world, raycastWorld: raycastWorld)
        }
    }

    func newItem() {
        itemIDs.append(UUID())
        target = .item
    }

    func detectorToggled() {
        detector.setEnabled(detectorEnabled)
    }

    func bandToggled() {
        let band: Float = bandOn ? 0.15 : .infinity
        Task { await engine.setDepthBand(band) }
    }

    func radiusChanged() {
        let metres = Float(radiusCentimetres / 100)
        Task { await engine.setRadius(metres) }
    }

    func reset() {
        itemIDs = []
        rows = []
        removeMarkers()
        Task { await engine.reset() }
    }

    func undoLastTap() {
        Task {
            let undone = await engine.undoLastTap()
            validationText = undone ? "Last tap undone." : "Nothing to undo."
        }
    }

    // MARK: - Showing the results

    private func pollSnapshots() async {
        while !Task.isCancelled {
            apply(await engine.snapshot())
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func apply(_ snapshot: MeasureDebugSnapshot) {
        // The engine hands out the same snapshot until something changes, so nothing is redrawn in between.
        guard snapshot.version != appliedVersion else { return }
        appliedVersion = snapshot.version
        if let floorY = snapshot.floorY {
            floorText = String(format: "Floor: y = %.2f m (%d planes). Tracking: %@",
                               floorY, snapshot.planeCount, String(describing: snapshot.tracking))
        } else {
            floorText = "Floor: not found yet. Move the iPhone over the floor."
        }
        if let valid = snapshot.depthValidShare, let high = snapshot.depthHighShare {
            depthText = String(format: "Depth: %.0f %% of the picture has a reading, %.0f %% high confidence",
                               valid * 100, high * 100)
        }
        rows = ([subjectID] + itemIDs + snapshot.detectedOrder).compactMap { id in
            guard snapshot.anchors[id] != nil || snapshot.detectedKinds[id] != nil else { return nil }
            let itemName = name(of: id, in: snapshot)
            let text = Self.summary(name: itemName, result: snapshot.results[id])
            return MeasureDebugRow(id: id, text: text)
        }
        redrawMarkers(snapshot)
    }

    /// How the native camera image lands on the screen (normalised to normalised), for drawing over the picture.
    private static func displayTransform(of view: ARView?) -> CGAffineTransform? {
        guard let view, let frame = view.session.currentFrame, view.bounds.width > 0 else { return nil }
        return frame.displayTransform(viewRotationAngle: 90, viewportSize: view.bounds.size)
    }

    private func name(of id: UUID, in snapshot: MeasureDebugSnapshot) -> String {
        if id == subjectID { return "Subject" }
        if let kind = snapshot.detectedKinds[id] {
            let sameKind = snapshot.detectedOrder.filter { snapshot.detectedKinds[$0] == kind }
            return "\(kind.debugName) \((sameKind.firstIndex(of: id) ?? 0) + 1)"
        }
        let number = (itemIDs.firstIndex(of: id) ?? 0) + 1
        return "Item \(number)"
    }

    private static func summary(name: String, result: EquipmentResult?) -> String {
        guard let result else { return "\(name): no result yet (the floor is needed)" }
        var parts = ["\(name): \(result.status)", "\(result.pointCount) points"]
        if result.status == .measured {
            parts.append("height \(centimetres(result.height))")
            parts.append("distance \(centimetres(result.distanceToSubject))")
            if let offset = result.floorOffset {
                parts.append(String(format: "floor position (%.0f, %.0f) cm", offset.x * 100, offset.y * 100))
            }
        }
        return parts.joined(separator: " · ")
    }

    private static func centimetres(_ metres: Float?) -> String {
        guard let metres else { return "not measured" }
        return String(format: "%.0f cm", metres * 100)
    }

    private static func validation(depthWorld: SIMD3<Float>, raycastWorld: SIMD3<Float>?) -> String {
        guard let raycastWorld else { return "Depth point found, but ARKit's raycast found no surface to compare." }
        let difference = simd_distance(depthWorld, raycastWorld)
        let text = String(format: "Depth and raycast differ by %.1f cm", difference * 100)
        return difference > validationLimitMetres ? text + ": check the axes and the orientation" : text + ": ok"
    }

    // MARK: - Taps on the AR view

    private func targetID() -> UUID {
        guard target == .item else { return subjectID }
        if itemIDs.isEmpty { itemIDs.append(UUID()) }
        return itemIDs[itemIDs.count - 1]
    }

    /// The tapped view point as a point of the native camera image (0 to 1, top-left origin).
    /// The current ARFrame is only looked at here and never stored.
    private func imagePoint(forViewPoint point: CGPoint) -> SIMD2<Float>? {
        guard let frame = arView.session.currentFrame else { return nil }
        let size = arView.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }
        // 90 degrees is portrait, the only orientation this app supports.
        let imageToView = frame.displayTransform(viewRotationAngle: 90, viewportSize: size)
        let viewPoint = CGPoint(x: point.x / size.width, y: point.y / size.height)
        let image = viewPoint.applying(imageToView.inverted())
        guard (0...1).contains(image.x), (0...1).contains(image.y) else { return nil }
        return SIMD2(Float(image.x), Float(image.y))
    }

    private func raycastPosition(at point: CGPoint) -> SIMD3<Float>? {
        let hits = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .any)
        guard let hit = hits.first else { return nil }
        let column = hit.worldTransform.columns.3
        return SIMD3(column.x, column.y, column.z)
    }

    // MARK: - Markers in the AR view

    /// Thin flat shapes, no balls: a small white cube on each tap; for each measured item a flat square on the floor
    /// at its base (green, orange for the subject) and one at its top (blue), joined by a thin vertical line.
    private func redrawMarkers(_ snapshot: MeasureDebugSnapshot) {
        removeMarkers()
        for points in snapshot.anchors.values {
            points.forEach { addBox(size: SIMD3(repeating: 0.015), at: $0, color: .white) }
        }
        guard let floorY = snapshot.floorY else { return }
        for (id, centres) in snapshot.centres {
            guard let base = centres.baseCentre, let top = centres.topCentre else { continue }
            let foot = SIMD3(base.x, floorY, base.y)
            addSquare(at: foot, color: id == subjectID ? .orange : .green)
            addSquare(at: top, color: .blue)
            addLine(from: foot, toHeight: top.y, color: .white)
        }
    }

    /// A flat square, 10 cm by 10 cm and 5 mm thick, lying at `position`.
    private func addSquare(at position: SIMD3<Float>, color: UIColor) {
        addBox(size: SIMD3(0.10, 0.005, 0.10), at: position, color: color)
    }

    /// A thin vertical line (a box 6 mm wide) from `foot` up to the height `top`.
    private func addLine(from foot: SIMD3<Float>, toHeight top: Float, color: UIColor) {
        let height = top - foot.y
        guard height > 0 else { return }
        addBox(size: SIMD3(0.006, height, 0.006), at: SIMD3(foot.x, foot.y + height / 2, foot.z), color: color)
    }

    private func addBox(size: SIMD3<Float>, at position: SIMD3<Float>, color: UIColor) {
        let material = SimpleMaterial(color: color, isMetallic: false)
        let entity = ModelEntity(mesh: .generateBox(size: size), materials: [material])
        let anchor = AnchorEntity(world: position)
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)
        markers.append(anchor)
    }

    private func removeMarkers() {
        markers.forEach { arView.scene.removeAnchor($0) }
        markers = []
    }
}
#endif
