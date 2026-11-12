import ARKit
import CoreGraphics
import MeasureKit
import MeasureKitVision
import Observation

enum ScanScreen: Equatable {

    case starting
    case scanning
    case cameraDenied
    case lidarUnsupported
    case failed(String)
}

@Observable
final class ScanViewModel {
    private(set) var screen = ScanScreen.starting

    var draftSetup: Setup

    @ObservationIgnored let pointCloud = PointCloudScene()

    @ObservationIgnored private let makeScan: () -> ScanSession
    @ObservationIgnored private let camera: any CameraPermission
    @ObservationIgnored private var scan: ScanSession?
    @ObservationIgnored private var stateTask: Task<Void, Never>?
    @ObservationIgnored private var pointsTask: Task<Void, Never>?
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private let subjectSegmenter: any SubjectSegmenting
    @ObservationIgnored private var subjectTask: Task<Void, Never>?
    @ObservationIgnored var storageController: StorageController
    @ObservationIgnored private var detector: (any EquipmentDetecting)?
    @ObservationIgnored private var detectTask: Task<Void, Never>?
    @ObservationIgnored private var isDetecting = false
    private var tracker = EquipmentTracker()
    /// The points of the subject and of every accepted item, for distance and height (A10-41, A10-21).
    @ObservationIgnored private var measurements = ScanMeasurements()
    /// Stands for the subject in `measurements`.
    @ObservationIgnored private let subjectID = UUID()
    /// The draft equipment each accepted tracker item became.
    @ObservationIgnored private var equipmentIDs: [Int: UUID] = [:]
    /// The newest frame, for a tap on the subject.
    @ObservationIgnored private var latestFrame: ScanFrame?
    /// The lowest floor plane ARKit has found so far; nil until it finds one.
    @ObservationIgnored private var floorY: Float?

    init(
        makeScan: @escaping () -> ScanSession = { ScanSession() },
        camera: any CameraPermission = SystemCameraPermission(),
        detector: (any EquipmentDetecting)? = nil,
        subjectSegmenter: any SubjectSegmenting = SubjectSegmenter(),
        storageController: StorageController? = nil
    ) {
        self.subjectSegmenter = subjectSegmenter
        self.makeScan = makeScan
        self.camera = camera
        self.storageController = storageController ?? StorageController.shared
        self.draftSetup = Setup(setupName: "Untitled Setup")
        self.detector = detector
    }

    /// The running scan's ARKit session, for the camera view. Nil until scanning, and in tests.
    var arSession: ARSession? {
        scan?.session as? ARSession
    }

    // call this function when scanning, adding an equipment when model catch equipment
    func addDraftEquipment(_ equipment: Equipment) {
        draftSetup.nodes.append(equipment)
    }

    /// The chosen subject's 3D spot. Nil until the subject tap exists (owner open).
    var subject: SIMD3<Float>?

    /// The subject's mask in the newest camera's picture. It is the subject's depth points from the tap, projected
    /// into each new camera, so it stays on the product as the phone moves. Nil when none is in view.
    private(set) var subjectMask: InstanceMask?
    /// The subject's depth points from the tap's mask (world space, at most `maxSubjectPoints`).
    @ObservationIgnored private var subjectPoints: [SIMD3<Float>] = []
    private static let maxSubjectPoints = 4000

    /// Finish Scan is enabled (A10-62 rule, from the overlay). False before the first look.
    var canFinish: Bool {
        overlay(in: .zero)?.canFinish ?? false
    }

    /// The camera at the latest look, to lay the masks over the picture (A10-62). Nil before the first look.
    var overlayCamera: CameraModel? {
        tracker.camera
    }

    /// What the scan screen draws over the camera (A10-62). Nil before the first look.
    func overlay(in screenSize: CGSize) -> ScanOverlay? {
        tracker.overlay(subject: subject, subjectMask: subjectMask, screenSize: screenSize)
    }

    /// One frame through detection → tracking → overlay (A10-62). Internal so tests can call it.
    /// Skips the frame when the last look was under 0.1 s ago or a look is still running.
    /// A frame without depth or a failed detection counts as a look that saw nothing.
    func detect(in frame: ScanFrame) async {
        floorY = FloorPicker.floorY(frame.planes.map(\.horizontalPlane)) ?? floorY
        guard !isDetecting, tracker.wantsLook(at: frame.timestamp), let detector else { return }
        isDetecting = true
        defer { isDetecting = false }
        var found: [EquipmentDetection] = []
        if frame.depth != nil {
            found = (try? await detector.detect(in: frame)) ?? []
        }
        guard !Task.isCancelled else { return }
        for item in tracker.look(found, depth: frame.depth, camera: frame.camera, at: frame.timestamp) {
            let equipment = Self.equipment(for: item)
            equipmentIDs[item.id] = equipment.id
            addDraftEquipment(equipment)
        }
        measureAcceptedItems(in: frame)
        subjectMask = DepthSampler.projectedMask(of: subjectPoints, camera: frame.camera)
    }

    /// Adds this look's points of every accepted item. Pending items add nothing (A10-21).
    private func measureAcceptedItems(in frame: ScanFrame) {
        guard let depth = frame.depth else { return }
        for seen in tracker.acceptedSightings {
            guard let id = equipmentIDs[seen.id] else { continue }
            measurements.add(to: id, box: seen.box, mask: seen.mask, depth: depth, camera: frame.camera)
        }
    }

    /// Half the side of the square of depth around a tap, as a fraction of the picture (about 12% wide in all).
    static let tapHalfSize = 0.06

    /// The photographer taps the subject on the camera view. Uses the newest frame the scan delivered.
    /// - Returns: false when there is no frame yet, the tap is off the picture, or there is no good depth under it;
    ///   the subject is then unchanged.
    @discardableResult
    func setSubject(atScreen tap: CGPoint, screenSize: CGSize) -> Bool {
        guard let latestFrame else { return false }
        return setSubject(atScreen: tap, screenSize: screenSize, in: latestFrame)
    }

    /// Same as `setSubject(atScreen:screenSize:)`, on a given frame. Internal so tests can call it.
    @discardableResult
    func setSubject(atScreen tap: CGPoint, screenSize: CGSize, in frame: ScanFrame) -> Bool {
        guard let depth = frame.depth,
              let point = ScanOverlay.picturePoint(fromScreen: tap, camera: frame.camera, screenSize: screenSize)
        else { return false }
        let box = NormalizedBox.around(x: point.x, y: point.y, halfSize: Self.tapHalfSize)
        let spot = DepthSampler.worldPoints(in: box, depth: depth, camera: frame.camera,
                                            maxRange: DepthSampler.maxRange)
        guard let centre = Geometry.medianPoint(spot) else { return false }
        measurements.remove(subjectID)
        measurements.add(to: subjectID, box: box, mask: nil, depth: depth, camera: frame.camera)
        subject = centre
        subjectMask = nil
        subjectPoints = []
        subjectTask?.cancel()
        subjectTask = Task { [weak self, subjectSegmenter] in
            let mask = await subjectSegmenter.mask(atNative: point, in: frame)
            guard let mask, !Task.isCancelled else { return }
            self?.useSubjectMask(mask, in: frame)
        }
        return true
    }

    /// Waits for the mask of the latest tap (or its failure). Internal so tests can wait for it.
    func subjectMaskSettled() async {
        await subjectTask?.value
    }

    /// The mask's depth points replace the patch's: the subject's base is then the product's own bottom band.
    /// A mask with no good depth is ignored and the patch stays.
    private func useSubjectMask(_ mask: InstanceMask, in frame: ScanFrame) {
        let points = frame.depth.map {
            DepthSampler.worldPoints(in: mask, depth: $0, camera: frame.camera, maxRange: DepthSampler.maxRange)
        } ?? []
        guard let depth = frame.depth, let box = MaskMapping.bounds(of: mask),
              let centre = Geometry.medianPoint(points) else { return }
        measurements.remove(subjectID)
        measurements.add(to: subjectID, box: box, mask: mask, depth: depth, camera: frame.camera)
        subject = centre
        let step = max(1, points.count / Self.maxSubjectPoints)
        subjectPoints = stride(from: 0, to: points.count, by: step).map { points[$0] }
        subjectMask = DepthSampler.projectedMask(of: subjectPoints, camera: frame.camera)
    }

    /// Writes each measured item's distance, height and plan position onto its draft equipment.
    /// The plan has the phone's side at the bottom, 100 points to the metre (as the diagram draws it).
    /// An item that could not be measured keeps empty values and stays at the centre.
    private func writeMeasurements() {
        guard let subject, let camera = tracker.camera else { return }
        let phone = camera.cameraToWorld.columns.3
        let towardPhone = SIMD2(phone.x - subject.x, phone.z - subject.z)
        let results = measurements.results(subject: subjectID, floorY: floorY ?? 0)
        for equipment in draftSetup.nodes {
            guard let result = results[equipment.id], result.status == .measured,
                  let distance = result.distanceToSubject, let offset = result.floorOffset else { continue }
            let plan = PlanLayout.planOffset(offset, towardViewer: towardPhone)
            equipment.distance = Self.metres(distance)
            equipment.position = CGPoint(x: Double(plan.x) * 100, y: Double(plan.y) * 100)
            if floorY != nil, let height = result.height {
                equipment.height = Self.metres(height)
            }
        }
    }

    /// "1.28": a plain number of metres, as `Equipment.syncDistanceFromPosition` writes it. The views add the unit.
    private static func metres(_ value: Float) -> String {
        String(format: "%.2f", value)
    }

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
        collectPoints(from: newScan)
        detectEquipment(from: newScan)
        do {
            try newScan.start()
            scan = newScan
            screen = .scanning
        } catch let error as ScanSessionError {
            stopListening()
            handle(.failed(error))
        } catch {
            stopListening()
            handle(.failed(ScanSessionError(error)))
        }
    }

    /// Called when the app comes back to the front, for example from Settings.
    /// If the user turned the camera on there, the scan starts.
    func appBecameActive() async {
        guard screen == .cameraDenied, camera.status == .authorized else { return }
        scan = nil
        screen = .starting
        await start()
    }

    func finishTapped() {
        insertDraftSetup()
        stopListening()
        writeMeasurements()
        scan?.stop()
    }

    func closeTapped() {
        deleteDraftSetup()
        stopListening()
        scan?.discard()
    }

     func handle(_ state: ScanSessionState) {
        switch state {
        case .failed(.cameraDenied):
            screen = .cameraDenied
        case .failed(.lidarUnsupported):
            screen = .lidarUnsupported
        case .failed(let error):
            screen = .failed(Self.message(for: error))
        case .idle, .running, .interrupted, .stopped, .discarded:
            break
        }
    }

    private func cameraAllowed() async -> Bool {
        switch camera.status {
        case .authorized: true
        case .notDetermined: await camera.request()
        case .denied: false
        }
    }

    private func listen(to scan: ScanSession) {
        stateTask?.cancel()
        let states = scan.states()
        stateTask = Task { [weak self] in
            for await state in states {
                self?.handle(state)
            }
        }
    }

    private func collectPoints(from scan: ScanSession) {
        pointsTask?.cancel()
        let frames = scan.frames()
        let collector = RoomPointsCollector()
        pointsTask = Task { [weak self] in
            for await frame in frames {
                let added = await collector.add(frame)
                guard !Task.isCancelled else { return }
                self?.pointCloud.add(added)
            }
        }
    }

    /// Listens to the same frames as the points, at its own pace (A10-62).
    private func detectEquipment(from scan: ScanSession) {
        detectTask?.cancel()
        let frames = scan.frames()
        detectTask = Task { [weak self] in
            if self?.detector == nil {
                let loaded = await Self.loadDetector()
                self?.detector = loaded
            }
            for await frame in frames {
                guard let self, !Task.isCancelled else { return }
                self.latestFrame = frame
                await self.detect(in: frame)
            }
        }
    }

    /// Loads the YOLOE model off the main actor, so the screen doesn't freeze. Nil if the model is missing.
    @concurrent nonisolated private static func loadDetector() async -> (any EquipmentDetecting)? {
        try? EquipmentDetector()
    }

    /// An accepted item as a draft equipment (Amadeus, 12 Nov: option A). Label and diagram position
    /// are left for the 2D Diagram story.
    private static func equipment(for item: TrackedItem) -> Equipment {
        let category: EquipmentCategory = EquipmentKind(modelLabel: item.label) == .camera ? .camera : .light
        return Equipment(category: category, name: ScanOverlay.name(for: item))
    }

    private func stopListening() {
        stateTask?.cancel()
        pointsTask?.cancel()
        detectTask?.cancel()
    }

    private static func message(for error: ScanSessionError) -> String {
        switch error {
        case .sessionFailed(let description): description
        case .alreadyStarted: "The scan was already started."
        case .cameraDenied, .lidarUnsupported: ""
        }
    }
    
    func deleteDraftSetup() {
        storageController.deleteSetup(draftSetup)
    }
    
    func insertDraftSetup() {
        storageController.addSetup(draftSetup)
    }
}
