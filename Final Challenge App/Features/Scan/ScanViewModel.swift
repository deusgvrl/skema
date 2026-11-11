import Observation

/// State and actions for ScanView.
/// Reads and writes data only through StorageController, and reloads on appear and after every change.

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

    @ObservationIgnored private let makeScan: () -> ScanSession
    @ObservationIgnored private let camera: any CameraPermission
    @ObservationIgnored private var scan: ScanSession?
    @ObservationIgnored private var stateTask: Task<Void, Never>?
    @ObservationIgnored private var isStarting = false

    init(
        makeScan: @escaping () -> ScanSession = { ScanSession() },
        camera: any CameraPermission = SystemCameraPermission()
    ) {
        self.makeScan = makeScan
        self.camera = camera
        self.draftSetup = Setup(setupName: "")
    }

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
        do {
            try newScan.start()
            scan = newScan
            screen = .scanning
        } catch let error as ScanSessionError {
            stateTask?.cancel()
            handle(.failed(error))
        } catch {
            stateTask?.cancel()
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

    /// Cancel, or back to Setups from Review: stops the camera and throws the scan away.
    func closeTapped() {
        stateTask?.cancel()
        scan?.discard()
    }

    /// Turns a session state into what the screen shows. Internal so tests can call it.
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

    private static func message(for error: ScanSessionError) -> String {
        switch error {
        case .sessionFailed(let description): description
        case .alreadyStarted: "The scan was already started."
        case .cameraDenied, .lidarUnsupported: ""
        }
    }
}
