import ARKit
import CoreGraphics
import MeasureKit
import Observation

/// What a tap on the camera view sets.
enum LiDARTapKind: Equatable {
    case subject
    case light
    case camera
}

/// A light or camera the photographer tapped: its anchor, and what the measuring code finds of it so far.
struct LiDARScanItem: Identifiable {
    /// Also the id of the draft `Equipment`.
    let id: UUID
    let kind: LiDARTapKind
    let name: String
    /// The LiDAR point that was tapped: it picks the item's vertical column.
    let anchor: SIMD3<Float>
    /// What the measuring code finds so far; nil until there is a subject.
    fileprivate(set) var result: EquipmentResult?
}

/// The LiDAR-only tap scan (a second scan screen, no object detection). The photographer taps the subject and each
/// light or camera. A tap picks a LiDAR point; its vertical column (10 cm radius, from 3 cm above the floor to 3 m) is
/// collected on every frame (the A10-41 painted items), and Finish writes distance, height and plan position onto the
/// draft equipment, ready to edit in the lighting plan.
@Observable
final class LiDARScanViewModel {
    private(set) var screen = ScanScreen.starting
    var kind = LiDARTapKind.subject
    var draftSetup = Setup(setupName: "")
    private(set) var items: [LiDARScanItem] = []
    /// The subject's anchor, nil until it is tapped.
    private(set) var subject: SIMD3<Float>?
    private(set) var subjectResult: EquipmentResult?
    /// A short hint after a tap that did nothing. Cleared by the next tap.
    private(set) var message: String?
    /// The newest camera, to lay masks and tags over the picture. Nil before the first frame.
    private(set) var camera: CameraModel?

    @ObservationIgnored private let makeScan: () -> ScanSession
    @ObservationIgnored private let cameraPermission: any CameraPermission
    @ObservationIgnored private let storageController: StorageController
    @ObservationIgnored private var scan: ScanSession?
    @ObservationIgnored private var stateTask: Task<Void, Never>?
    @ObservationIgnored private var framesTask: Task<Void, Never>?
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var measurements = ScanMeasurements()
    @ObservationIgnored private let subjectID = UUID()
    @ObservationIgnored private var kindCounts: [LiDARTapKind: Int] = [:]
    @ObservationIgnored private var latestFrame: ScanFrame?
    @ObservationIgnored private var floorY: Float?
    @ObservationIgnored private var lastCollect: Double?

    /// The painted column (the A10-41 debug screen's rule): 10 cm around the tapped axis, from 3 cm above the floor
    /// up to 3 m above it.
    static let columnRadius: Float = 0.10
    static let columnFloorGap: Float = 0.03
    static let columnHeight: Float = 3.0
    /// Five frames a second are plenty for items that do not move.
    static let collectInterval: Double = 0.2

    init(
        makeScan: @escaping () -> ScanSession = { ScanSession() },
        camera: any CameraPermission = SystemCameraPermission(),
        storageController: StorageController? = nil
    ) {
        self.makeScan = makeScan
        self.cameraPermission = camera
        self.storageController = storageController ?? StorageController.shared
    }

    var arSession: ARSession? { scan?.session as? ARSession }

    /// Finish Scan: a subject, one camera and one light (the same rule as the automatic scan).
    var canFinish: Bool {
        ScanOverlay.canFinish(hasSubject: subject != nil,
                              acceptedCameras: items.filter { $0.kind == .camera }.count,
                              acceptedLights: items.filter { $0.kind == .light }.count)
    }

    // MARK: Taps

    /// A tap on the camera view, on the newest frame the scan delivered.
    func tap(atScreen point: CGPoint, screenSize: CGSize) {
        guard let latestFrame else { return }
        tap(atScreen: point, screenSize: screenSize, in: latestFrame)
    }

    /// Same as `tap(atScreen:screenSize:)`, on a given frame. Internal so tests can call it.
    func tap(atScreen point: CGPoint, screenSize: CGSize, in frame: ScanFrame) {
        message = nil
        camera = frame.camera
        floorY = FloorPicker.floorY(frame.planes.map(\.horizontalPlane)) ?? floorY
        guard let picture = ScanOverlay.picturePoint(fromScreen: point, camera: frame.camera, screenSize: screenSize)
        else { return }
        // A tap on an item's tag spot (in a light or camera mode) removes it.
        if kind != .subject, let hit = item(atScreen: point, screenSize: screenSize) {
            remove(hit)
            return
        }
        guard floorY != nil else {
            message = "Point the phone at the floor first"
            return
        }
        guard let depth = frame.depth,
              let anchor = DepthSampler.nearestPoint(toNormalized: SIMD2(Float(picture.x), Float(picture.y)),
                                                     depth: depth, camera: frame.camera) else {
            message = "No LiDAR depth there"
            return
        }
        if kind == .subject {
            measurements.remove(subjectID)
            subject = anchor
        } else {
            addItem(kind, anchor: anchor)
        }
        collect(from: frame)
    }

    private func addItem(_ kind: LiDARTapKind, anchor: SIMD3<Float>) {
        let number = (kindCounts[kind] ?? 0) + 1
        kindCounts[kind] = number
        let name = (kind == .camera ? "Camera" : "Studio Lighting") + " \(number)"
        let equipment = Equipment(category: kind == .camera ? .camera : .light, name: name)
        items.append(LiDARScanItem(id: equipment.id, kind: kind, name: name, anchor: anchor))
        draftSetup.nodes.append(equipment)
    }

    private func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        draftSetup.nodes.removeAll { $0.id == id }
        measurements.remove(id)
    }

    /// How close (in points) a tap must be to an item's tag spot to count as a tap on it.
    static let removeRadius: CGFloat = 44

    /// The newest item whose tag spot is within `removeRadius` of the tap.
    private func item(atScreen point: CGPoint, screenSize: CGSize) -> UUID? {
        items.last { item in
            guard let spot = tagPosition(of: item.anchor, in: screenSize) else { return false }
            return hypot(spot.x - point.x, spot.y - point.y) <= Self.removeRadius
        }?.id
    }

    // MARK: Painting

    /// Takes one frame: collects the column of the subject and of every item and refreshes the live results.
    /// Internal so tests can call it.
    func collect(from frame: ScanFrame) {
        camera = frame.camera
        floorY = FloorPicker.floorY(frame.planes.map(\.horizontalPlane)) ?? floorY
        guard let depth = frame.depth, let floorY else { return }
        let heights = (floorY + Self.columnFloorGap)...(floorY + Self.columnHeight)
        func paint(around anchor: SIMD3<Float>, for id: UUID) {
            let points = DepthSampler.columnPoints(around: [anchor], radius: Self.columnRadius, betweenY: heights,
                                                   depth: depth, camera: frame.camera)
            measurements.add(points: points, to: id, camera: frame.camera)
        }
        if let subject {
            paint(around: subject, for: subjectID)
        }
        for item in items {
            paint(around: item.anchor, for: item.id)
        }
        refreshResults()
    }

    /// The live results, and the values written onto the draft equipment as soon as they exist, so what a tag says
    /// is saved really is on the equipment.
    private func refreshResults() {
        let results = measurements.results(subject: subjectID, floorY: floorY ?? 0)
        subjectResult = subject == nil ? nil : results[subjectID]
        for index in items.indices {
            items[index].result = results[items[index].id]
        }
        write(results)
    }

    /// Where a tag for `spot` goes on a screen of `size`; nil when the spot is not on the screen.
    func tagPosition(of spot: SIMD3<Float>, in size: CGSize) -> CGPoint? {
        camera.flatMap { ScanOverlay.screenPoint(of: spot, camera: $0, screenSize: size) }
    }

    /// "Studio Lighting 1 · 1.52 m · 1.20 m" once measured; just the name before that.
    func tagText(for item: LiDARScanItem) -> String {
        guard let values = Self.values(of: item.result, hasFloor: floorY != nil), let height = values.height else {
            return "\(item.name) ✓"
        }
        return "\(item.name) · \(Self.metres(values.distance)) m · \(Self.metres(height)) m"
    }

    /// The line under an item's name: whether its values are saved on the equipment, or why not.
    func statusText(for item: LiDARScanItem) -> String {
        guard let result = item.result else { return "Measuring…" }
        switch result.status {
        case .tooFewPoints: return Self.tooFewPointsText
        case .outOfRange: return Self.outOfRangeText
        case .measured:
            if Self.values(of: result, hasFloor: floorY != nil) != nil { return Self.savedText }
            return subject == nil ? "Waiting for the subject" : "Subject not measured, see its tag"
        }
    }

    func isSaved(_ item: LiDARScanItem) -> Bool {
        Self.values(of: item.result, hasFloor: floorY != nil) != nil
    }

    /// The line under the subject's name.
    var subjectStatusText: String {
        guard let result = subjectResult else { return "Measuring…" }
        switch result.status {
        case .tooFewPoints: return Self.tooFewPointsText
        case .outOfRange: return Self.outOfRangeText
        case .measured: return Self.savedText
        }
    }

    var subjectIsSaved: Bool { subjectResult?.status == .measured }

    static let savedText = "Saved"
    static let tooFewPointsText = "Not enough LiDAR points, tap again"
    static let outOfRangeText = "Too far, over 5 m"

    /// What is written onto an item's equipment: the one rule for "measured" that the tag and the writing share.
    private static func values(of result: EquipmentResult?, hasFloor: Bool) -> SavedValues? {
        guard let result, result.status == .measured,
              let distance = result.distanceToSubject, let offset = result.floorOffset else { return nil }
        return SavedValues(distance: distance, offset: offset, height: hasFloor ? result.height : nil)
    }

    private struct SavedValues {
        let distance: Float
        let offset: SIMD2<Float>
        let height: Float?
    }

    // MARK: Finish and the plan

    func finishTapped() {
        storageController.addSetup(draftSetup)
        stopListening()
        write(measurements.results(subject: subjectID, floorY: floorY ?? 0))
        scan?.stop()
    }

    func closeTapped() {
        storageController.deleteSetup(draftSetup)
        stopListening()
        scan?.discard()
    }

    /// Writes each measured item's distance, height and plan position onto its draft equipment: the plan has the
    /// phone's side at the bottom, 100 points to the metre (the same rules as the automatic scan). An item that could
    /// not be measured keeps empty values and stays at the centre. Done again at Finish with the final camera.
    private func write(_ results: [UUID: EquipmentResult]) {
        guard let subject, let camera else { return }
        let phone = camera.cameraToWorld.columns.3
        let towardPhone = SIMD2(phone.x - subject.x, phone.z - subject.z)
        for equipment in draftSetup.nodes {
            guard let values = Self.values(of: results[equipment.id], hasFloor: floorY != nil) else { continue }
            let plan = PlanLayout.planOffset(values.offset, towardViewer: towardPhone)
            equipment.distance = Self.metres(values.distance)
            equipment.position = CGPoint(x: Double(plan.x) * 100, y: Double(plan.y) * 100)
            if let height = values.height {
                equipment.height = Self.metres(height)
            }
        }
    }

    /// "1.28": a plain number of metres, as `Equipment.syncDistanceFromPosition` writes it. The views add the unit.
    private static func metres(_ value: Float) -> String {
        String(format: "%.2f", value)
    }

    private func stopListening() {
        stateTask?.cancel()
        framesTask?.cancel()
    }
}

// MARK: - Session

extension LiDARScanViewModel {
    func start() async {
        guard screen == .starting, scan == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        let newScan = makeScan()
        guard newScan.isLiDARSupported else {
            screen = .lidarUnsupported
            return
        }
        guard await cameraAllowed() else {
            screen = .cameraDenied
            return
        }
        listen(to: newScan)
        collectFrames(from: newScan)
        do {
            try newScan.start()
            scan = newScan
            screen = .scanning
        } catch {
            stopListening()
            handle(.failed(error as? ScanSessionError ?? ScanSessionError(error)))
        }
    }

    /// Called when the app comes back to the front, for example from Settings.
    func appBecameActive() async {
        guard screen == .cameraDenied, cameraPermission.status == .authorized else { return }
        scan = nil
        screen = .starting
        await start()
    }

    func handle(_ state: ScanSessionState) {
        switch state {
        case .failed(.cameraDenied): screen = .cameraDenied
        case .failed(.lidarUnsupported): screen = .lidarUnsupported
        case .failed(let error): screen = .failed(Self.message(for: error))
        case .idle, .running, .interrupted, .stopped, .discarded: break
        }
    }

    private func cameraAllowed() async -> Bool {
        switch cameraPermission.status {
        case .authorized: true
        case .notDetermined: await cameraPermission.request()
        case .denied: false
        }
    }

    private func listen(to scan: ScanSession) {
        stateTask?.cancel()
        let states = scan.states()
        stateTask = Task { [weak self] in
            for await state in states { self?.handle(state) }
        }
    }

    /// The newest frame for taps, and the painting five times a second.
    private func collectFrames(from scan: ScanSession) {
        framesTask?.cancel()
        let frames = scan.frames()
        framesTask = Task { [weak self] in
            for await frame in frames {
                guard !Task.isCancelled, let self else { return }
                self.latestFrame = frame
                if self.lastCollect.map({ frame.timestamp - $0 >= Self.collectInterval }) ?? true {
                    self.lastCollect = frame.timestamp
                    self.collect(from: frame)
                }
            }
        }
    }

    private static func message(for error: ScanSessionError) -> String {
        switch error {
        case .sessionFailed(let description): description
        case .alreadyStarted: "The scan was already started."
        case .cameraDenied, .lidarUnsupported: ""
        }
    }
}
