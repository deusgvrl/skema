import ARKit
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

    init(
        makeScan: @escaping () -> ScanSession = { ScanSession() },
        camera: any CameraPermission = SystemCameraPermission(),
        storageController: StorageController? = nil
    ) {
        self.makeScan = makeScan
        self.camera = camera
        self.storageController = storageController ?? StorageController.shared
        self.draftSetup = Setup(setupName: "Untitled Setup")
    }

    /// The running scan's ARKit session, for the camera view. Nil until scanning, and in tests.
    var arSession: ARSession? {
        scan?.session as? ARSession
    }

    // call this function when scanning, adding an equipment when model catch equipment
    func addDraftEquipment(_ equipment: Equipment) {
        draftSetup.nodes.append(equipment)
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

    private func stopListening() {
        stateTask?.cancel()
        pointsTask?.cancel()
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
