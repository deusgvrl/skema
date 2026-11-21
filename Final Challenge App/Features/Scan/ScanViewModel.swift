import ARKit
import CoreGraphics
import MeasureKit
import Observation

/// What a tap on the camera view sets.
enum ScanTapKind: Equatable {
    case floor
    case subject
    case light
    case camera
}

/// A light or camera the photographer tapped: its anchor, and what the measuring code finds of it so far.
struct ScanItem: Identifiable {
    /// Also the id of the draft `Equipment`.
    let id: UUID
    let kind: ScanTapKind
    let name: String
    /// The LiDAR point that was tapped: it picks the item's vertical column.
    let anchor: SIMD3<Float>
    /// What the measuring code finds so far; nil until there is a subject.
    fileprivate(set) var result: EquipmentResult?
}

/// The scan (LiDAR only, no object detection: the team chose taps after usability testing, 19 Nov 2026).
/// A guided sequence (Sketch UT Review T01–T10): the photographer taps the floor, the subject, the camera and each light,
/// and each tap sets the next thing still missing (`ScanStep`); a coaching panel explains each step on the first scan. A tap picks a LiDAR point; its vertical column
/// (10 cm radius, from 3 cm above the floor to 3 m) is collected on every frame (the A10-41 painted items), and Finish
/// writes distance, height and plan position onto the draft equipment, ready to edit in the lighting plan. While
/// scanning, tips say when tracking, light or distance goes badly (A10-69).
@Observable
final class ScanViewModel {
    private(set) var screen = ScanScreen.starting
    /// What the next tap sets. It follows `currentStep` after every tap; tests may set it directly.
    var kind = ScanTapKind.floor
    var draftSetup = Setup(setupName: "")
    private(set) var items: [ScanItem] = []
    /// The subject's anchor, nil until it is tapped.
    private(set) var subject: SIMD3<Float>?
    private(set) var subjectResult: EquipmentResult?
    /// A short hint after a tap that did nothing. Cleared by the next tap.
    private(set) var message: String?
    /// The newest camera, to lay the tags over the picture. Nil before the first frame.
    private(set) var camera: CameraModel?
    /// The tip shown while scanning ("Move slower", "More light"…), nil when the scan goes well (A10-69).
    private(set) var guidance: ScanGuidance?
    /// The tapped floor point, nil until the floor is tapped (step 1).
    private(set) var floorAnchor: SIMD3<Float>?
    /// The floor's height from the floor tap (`ScanFloor.height`), for the floor grid. Nil until tapped.
    private(set) var floorHeight: Float?
    /// The coaching panel (first scan, or after ?); a hint pill shows instead when it is hidden.
    private(set) var isTutorialVisible: Bool
    /// The step whose tap just landed, for the panel's short "done" state. The view clears it.
    private(set) var completedStep: ScanStep?
    /// Each item's collected points, as a world box, for its green outline.
    private(set) var itemBounds: [UUID: WorldBox] = [:]
    /// The subject's collected points, as a world box.
    private(set) var subjectBounds: WorldBox?

    @ObservationIgnored private let makeScan: () -> ScanSession
    @ObservationIgnored private let cameraPermission: any CameraPermission
    @ObservationIgnored let storageController: StorageController
    @ObservationIgnored private var scan: ScanSession?
    @ObservationIgnored private var stateTask: Task<Void, Never>?
    @ObservationIgnored private var framesTask: Task<Void, Never>?
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var measurements = ScanMeasurements()
    @ObservationIgnored private let subjectID = UUID()
    @ObservationIgnored private var kindCounts: [ScanTapKind: Int] = [:]
    @ObservationIgnored private var latestFrame: ScanFrame?
    /// The floor ARKit found, used until the floor is tapped.
    @ObservationIgnored private var planeFloorY: Float?
    @ObservationIgnored private let tutorial: ScanGuideSettings?
    /// Every tap that set something, newest last, for Undo.
    private var history: [TapRecord] = []
    @ObservationIgnored private var lastCollect: Double?
    @ObservationIgnored private var guidanceHold = GuidanceHold()

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
        storageController: StorageController? = nil,
        tutorial: ScanGuideSettings? = nil
    ) {
        self.makeScan = makeScan
        self.cameraPermission = camera
        self.storageController = storageController ?? StorageController.shared
        self.tutorial = tutorial
        self.isTutorialVisible = !(tutorial?.isTutorialDone ?? false)
    }

    /// The tapped floor, or ARKit's floor until then.
    private var floorY: Float? { floorHeight ?? planeFloorY }

    var hasFloor: Bool { floorAnchor != nil }

    /// Undo is on once a tap set something.
    var canUndo: Bool { !history.isEmpty }

    /// The first thing still missing: floor, subject, camera, light, then Finish.
    var currentStep: ScanStep {
        ScanStep.current(hasFloor: hasFloor, hasSubject: subject != nil,
                         cameras: items.filter { $0.kind == .camera }.count,
                         lights: items.filter { $0.kind == .light }.count)
    }

    // MARK: Tutorial

    /// Skip: hides the panel for this and every later scan.
    func skipTutorial() {
        isTutorialVisible = false
        tutorial?.isTutorialDone = true
    }

    /// ?: shows the panel again, at the current step.
    func replayTutorial() {
        isTutorialVisible = true
    }

    func clearCompletedStep() {
        completedStep = nil
    }

    /// After a tap: the next tap sets what is still missing, and reaching Finish counts as doing the tutorial.
    private func advance() {
        kind = currentStep.tapKind
        if currentStep == .finish { tutorial?.isTutorialDone = true }
    }

    var arSession: ARSession? { scan?.session as? ARSession }

    /// ✕ asks "Cancel This Scan?" first only while scanning; the message screens leave straight away.
    var asksBeforeLeaving: Bool { screen == .scanning }

    /// Finish Scan: a subject, one camera and one light (`ScanOverlay.canFinish`).
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
        planeFloorY = FloorPicker.floorY(frame.planes.map(\.horizontalPlane)) ?? planeFloorY
        guard let picture = ScanOverlay.picturePoint(fromScreen: point, camera: frame.camera, screenSize: screenSize)
        else { return }
        // A tap on an item's tag spot (in a light or camera mode) removes it.
        if kind == .light || kind == .camera, let hit = item(atScreen: point, screenSize: screenSize) {
            remove(hit)
            advance()
            return
        }
        guard kind == .floor || floorY != nil else {
            message = "Point the phone at the floor first"
            return
        }
        guard let depth = frame.depth,
              let anchor = DepthSampler.nearestPoint(toNormalized: SIMD2(Float(picture.x), Float(picture.y)),
                                                     depth: depth, camera: frame.camera) else {
            message = "No LiDAR depth there"
            return
        }
        switch kind {
        case .floor:
            history.append(.floor(previousAnchor: floorAnchor, previousHeight: floorHeight))
            floorAnchor = anchor
            floorHeight = ScanFloor.height(tappedY: anchor.y, planes: frame.planes.map(\.horizontalPlane))
        case .subject:
            history.append(.subject(previous: subject))
            measurements.remove(subjectID)
            subjectBounds = nil
            subject = anchor
        case .light, .camera:
            // A10-106 case 12: a light tap inside a light's grown box is that light again, not a new one.
            if kind == .light, let light = light(containing: anchor) {
                message = "Already tapped: Light \(light.name.split(separator: " ").last ?? "")"
                return
            }
            addItem(kind, anchor: anchor)
        }
        completedStep = ScanStep(completing: kind)
        advance()
        collect(from: frame)
    }

    private func addItem(_ kind: ScanTapKind, anchor: SIMD3<Float>) {
        let number = (kindCounts[kind] ?? 0) + 1
        kindCounts[kind] = number
        let name = (kind == .camera ? "Camera" : "Studio Lighting") + " \(number)"
        let equipment = Equipment(category: kind == .camera ? .camera : .light, name: name)
        items.append(ScanItem(id: equipment.id, kind: kind, name: name, anchor: anchor))
        history.append(.item(equipment.id))
        draftSetup.nodes.append(equipment)
        // A light is measured at the middle of its head; a camera keeps the top-point rule for now.
        if kind == .light { measurements.setRule(.middle, for: equipment.id) }
    }

    /// The light whose grown box holds `point`, if any.
    private func light(containing point: SIMD3<Float>) -> ScanItem? {
        items.first { $0.kind == .light && measurements.bigBox(for: $0.id)?.contains(point) == true }
    }

    private func remove(_ id: UUID) {
        history.removeAll { $0 == .item(id) }
        items.removeAll { $0.id == id }
        draftSetup.nodes.removeAll { $0.id == id }
        measurements.remove(id)
        itemBounds[id] = nil
    }

    /// Undo: takes back the newest tap that set something (floor, subject, camera or light), and the next tap sets
    /// what is missing again.
    func undoTapped() {
        guard let last = history.popLast() else { return }
        message = nil
        completedStep = nil
        switch last {
        case let .floor(previousAnchor, previousHeight):
            floorAnchor = previousAnchor
            floorHeight = previousHeight
        case .subject(let previous):
            measurements.remove(subjectID)
            subjectBounds = nil
            subject = previous
        case .item(let id):
            // The next item of the kind takes the undone one's number again.
            if let item = items.first(where: { $0.id == id }), let number = item.name.split(separator: " ").last,
               Int(number) == kindCounts[item.kind] {
                kindCounts[item.kind] = (kindCounts[item.kind] ?? 1) - 1
            }
            remove(id)
        }
        refreshResults()
        advance()
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
        planeFloorY = FloorPicker.floorY(frame.planes.map(\.horizontalPlane)) ?? planeFloorY
        guard let depth = frame.depth, let floorY else { return }
        let heights = (floorY + Self.columnFloorGap)...(floorY + Self.columnHeight)
        func paint(around anchor: SIMD3<Float>, for id: UUID) {
            let points = DepthSampler.columnPoints(around: [anchor], radius: Self.columnRadius, betweenY: heights,
                                                   depth: depth, camera: frame.camera)
            measurements.add(points: points, to: id, camera: frame.camera)
        }
        if let subject {
            paint(around: subject, for: subjectID)
            subjectBounds = measurements.bounds(for: subjectID).map { WorldBox(min: $0.min, max: $0.max) }
        }
        for item in items {
            if item.kind == .light {
                // A10-106: a light is the surface painted from its tap; its outline is its grown box.
                paintSurface(of: item, depth: depth, camera: frame.camera, floorY: floorY)
                itemBounds[item.id] = measurements.bigBox(for: item.id)
            } else {
                paint(around: item.anchor, for: item.id)
                itemBounds[item.id] = measurements.bounds(for: item.id).map { WorldBox(min: $0.min, max: $0.max) }
            }
        }
        refreshResults()
    }

    /// One frame of a light: the paint bucket from its tapped point, where the point is in this frame's picture.
    private func paintSurface(of item: ScanItem, depth: DepthFrame, camera: CameraModel, floorY: Float) {
        guard let pixel = DepthSampler.project(item.anchor, camera: camera) else { return }
        let points = DepthGrouping.surface(fromNormalized: pixel / camera.imageResolution, depth: depth, camera: camera,
                                           floorY: floorY)
        measurements.addSurface(points: points, to: item.id, camera: camera)
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

    /// The green outline around an item on a screen of `size`: its world box's corners, projected. Nil before it has
    /// points or when it is off the screen.
    func box(for item: ScanItem, in size: CGSize) -> CGRect? {
        box(of: itemBounds[item.id], in: size)
    }

    /// The green outline around the subject.
    func subjectBox(in size: CGSize) -> CGRect? {
        box(of: subjectBounds, in: size)
    }
    private func box(of bounds: WorldBox?, in size: CGSize) -> CGRect? {
        guard let camera, let bounds else { return nil }
        return ScanOverlay.screenBox(of: bounds.corners, camera: camera, screenSize: size)
    }

    /// The tag's title (Sketch T09): "Camera", "Light", numbered only when there is more than one of the kind.
    func shortTitle(for item: ScanItem) -> String {
        let base = item.kind == .camera ? "Camera" : "Light"
        let sameKind = items.filter { $0.kind == item.kind }
        guard sameKind.count > 1, let index = sameKind.firstIndex(where: { $0.id == item.id }) else { return base }
        return "\(base) \(index + 1)"
    }

    /// "Studio Lighting 1 · 1.52 m · 1.20 m" once measured; just the name before that.
    func tagText(for item: ScanItem) -> String {
        guard let values = Self.values(of: item.result, hasFloor: floorY != nil), let height = values.height else {
            return "\(item.name) ✓"
        }
        return "\(item.name) · \(Self.metres(values.distance)) m · \(Self.metres(height)) m"
    }

    /// The line under an item's name: whether its values are saved on the equipment, or why not.
    func statusText(for item: ScanItem) -> String {
        guard let result = item.result else { return "Measuring…" }
        switch result.status {
        case .tooFewPoints: return Self.tooFewPointsText
        case .outOfRange: return Self.outOfRangeText
        case .measured:
            if Self.values(of: result, hasFloor: floorY != nil) != nil { return Self.savedText }
            return subject == nil ? "Waiting for the subject" : "Subject not measured, see its tag"
        }
    }

    func isSaved(_ item: ScanItem) -> Bool {
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
        insertDraftSetup()
        stopListening()
        write(measurements.results(subject: subjectID, floorY: floorY ?? 0))
        draftSetup.alignAndOrientDiagram()
        storageController.save()
        scan?.stop()
    }

    func closeTapped() {
        storageController.deleteSetup(draftSetup)
        stopListening()
        scan?.discard()
    }

    /// Puts the draft setup into storage: at Finish, and for "Add Equipment Manually" on the message screens.
    func insertDraftSetup() {
        storageController.addSetup(draftSetup)
    }

    /// Writes the subject's height onto the setup, and each measured item's distance, height and plan position onto
    /// its draft equipment: the plan has the phone's side at the bottom, 100 points to the metre. An item that could
    /// not be measured keeps empty values and stays at the centre. Done again at Finish with the final camera.
    private func write(_ results: [UUID: EquipmentResult]) {
        guard let subject, let camera else { return }
        if floorY != nil, results[subjectID]?.status == .measured, let height = results[subjectID]?.height {
            draftSetup.subjectHeight = Self.metres(height)
        }
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
        guidance = nil
    }

    /// The tip for this frame, shown only once it held for a moment (`GuidanceHold`). Internal so tests can call it.
    func updateGuidance(for frame: ScanFrame) {
        let tip = ScanGuidance.guidance(tracking: frame.tracking, ambientIntensity: frame.ambientIntensity,
                                        depth: frame.depth)
        guidance = guidanceHold.update(tip, at: frame.timestamp)
    }
}

// MARK: - Session

extension ScanViewModel {
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

    /// The newest frame for taps, the tips on every frame, and the painting five times a second.
    private func collectFrames(from scan: ScanSession) {
        framesTask?.cancel()
        let frames = scan.frames()
        framesTask = Task { [weak self] in
            for await frame in frames {
                guard !Task.isCancelled, let self else { return }
                self.latestFrame = frame
                self.updateGuidance(for: frame)
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

/// One tap that set something, with what it replaced, so Undo can put it back.
private enum TapRecord: Equatable {
    case floor(previousAnchor: SIMD3<Float>?, previousHeight: Float?)
    case subject(previous: SIMD3<Float>?)
    case item(UUID)
}
