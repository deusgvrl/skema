import ARKit
import MeasureKit
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
    @ObservationIgnored var storageController: StorageController
    @ObservationIgnored private var detector: (any EquipmentDetecting)?
    @ObservationIgnored private var detectTask: Task<Void, Never>?
    @ObservationIgnored private var isDetecting = false
    private var tracker = EquipmentTracker()
    
    init (
        makeScan: @escaping () -> ScanSession = { ScanSession() },
        camera: any CameraPermission = SystemCameraPermission(),
        detector: (any EquipmentDetecting)? = nil,
        storageController: StorageController? = nil
    ) {
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
        tracker.overlay(subject: subject, screenSize: screenSize)
    }

    /// One frame through detection → tracking → overlay (A10-62). Internal so tests can call it.
    /// Skips the frame when the last look was under 0.1 s ago or a look is still running.
    /// A frame without depth or a failed detection counts as a look that saw nothing.
    func detect(in frame: ScanFrame) async {
        guard !isDetecting, tracker.wantsLook(at: frame.timestamp), let detector else { return }
        isDetecting = true
        defer { isDetecting = false }
        var found: [EquipmentDetection] = []
        if frame.depth != nil {
            found = (try? await detector.detect(in: frame)) ?? []
        }
        guard !Task.isCancelled else { return }
        for item in tracker.look(found, depth: frame.depth, camera: frame.camera, at: frame.timestamp) {
            addDraftEquipment(Self.equipment(for: item))
        }
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
