/// Runs the ARKit + LiDAR scan and collects depth points (A10-4).

import ARKit
import Foundation
import Synchronization

nonisolated final class ScanSession: NSObject, ARSessionDelegate, @unchecked Sendable {
    /// The session to draw the camera and the points with (A10-68). It is a real `ARSession` in the app.
    let session: any ARSessionControlling

    private let supportsLiDAR: @Sendable () -> Bool
    private let supportsMesh: @Sendable () -> Bool
    let renderer: ScanRendererChoice
    private let delegateQueue = DispatchQueue(label: "ScanSession.delegate", qos: .userInitiated)
    private let frameBroadcast = Broadcast<ScanFrame>(bufferSize: 1)
    private let stateBroadcast = Broadcast<ScanSessionState>(bufferSize: 8)
    private let store: Mutex<Store>

    private struct Store {
        var state = ScanSessionState.idle
        var throttle: FrameThrottle
        var planes = PlaneStore()
        /// The mesh choice `start` made, so the run that stops the plane search keeps it.
        var withMesh = false
        /// False once `stopPlaneDetection` ran: ARKit no longer looks for planes.
        var detectsPlanes = true
    }

    init(
        session: any ARSessionControlling = ARSession(),
        frameInterval: TimeInterval = 1.0 / 15.0,
        supportsLiDAR: @escaping @Sendable () -> Bool = { ScanSession.deviceSupportsLiDAR() },
        supportsMesh: @escaping @Sendable () -> Bool = { ScanSession.deviceSupportsMesh() },
        renderer: ScanRendererChoice = ScanRendererChoice(defaults: .standard)
    ) {
        self.session = session
        self.supportsLiDAR = supportsLiDAR
        self.supportsMesh = supportsMesh
        self.renderer = renderer
        self.store = Mutex(Store(throttle: FrameThrottle(minimumInterval: frameInterval)))
        super.init()
        session.delegateQueue = delegateQueue
        session.delegate = self
    }

    static func deviceSupportsLiDAR() -> Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    /// The room mesh (scene reconstruction) that RealityKit's occlusion uses to hide the outline behind real
    /// surfaces (A10-106). Not every LiDAR iPhone may offer it, so the app asks.
    static func deviceSupportsMesh() -> Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    static func makeConfiguration(withMesh: Bool = false, detectsPlanes: Bool = true) -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = [.sceneDepth]
        configuration.planeDetection = detectsPlanes ? [.horizontal] : []
        if withMesh { configuration.sceneReconstruction = .mesh }
        return configuration
    }

    /// False on iPhones without LiDAR. A10-67 shows its message when this is false.
    var isLiDARSupported: Bool {
        supportsLiDAR()
    }

    var state: ScanSessionState {
        store.withLock { $0.state }
    }

    var planes: [ScanPlane] {
        store.withLock { $0.planes.planes }
    }

    func frames() -> AsyncStream<ScanFrame> {
        frameBroadcast.stream()
    }

    func states() -> AsyncStream<ScanSessionState> {
        stateBroadcast.stream()
    }

    func start() throws {
        guard isLiDARSupported else { throw ScanSessionError.lidarUnsupported }
        // The room mesh only helps RealityKit hide the outline. Our own Metal view does not use it (D1).
        let withMesh = supportsMesh() && renderer == .arView
        try store.withLock { current in
            guard current.state == .idle else { throw ScanSessionError.alreadyStarted }
            current.state = .running
            current.withMesh = withMesh
        }
        stateBroadcast.yield(.running)
        session.run(Self.makeConfiguration(withMesh: withMesh), options: [.resetTracking, .removeExistingAnchors])
    }

    /// Stops ARKit's search for planes (A10-121). It runs the session once more with the same configuration minus plane
    /// detection and with no run options, so tracking and the anchors stay. It does nothing when the scan is not
    /// running or when the search is already off.
    func stopPlaneDetection() {
        let withMesh = store.withLock { current -> Bool? in
            guard current.state == .running, current.detectsPlanes else { return nil }
            current.detectsPlanes = false
            return current.withMesh
        }
        guard let withMesh else { return }
        session.run(Self.makeConfiguration(withMesh: withMesh, detectsPlanes: false), options: [])
    }

    func stop() {
        end(as: .stopped)
    }

    func discard() {
        end(as: .discarded)
    }

    // MARK: - Steps the delegate methods take (internal so tests can call them)

    /// True when the scan is running and the frame is not too soon after the last one.
    func acceptsFrame(at timestamp: TimeInterval) -> Bool {
        store.withLock { current in
            current.state == .running && current.throttle.accepts(timestamp)
        }
    }

    func deliver(_ frame: ScanFrame) {
        frameBroadcast.yield(frame)
    }

    func updatePlanes(_ planes: [ScanPlane]) {
        guard !planes.isEmpty else { return }
        store.withLock { current in
            guard !current.state.isFinished else { return }
            current.planes.upsert(planes)
        }
    }

    func removePlanes(_ ids: [UUID]) {
        store.withLock { $0.planes.remove(ids) }
    }

    func fail(with error: any Error) {
        end(as: .failed(ScanSessionError(error)))
    }

    func setInterrupted(_ interrupted: Bool) {
        let newState = store.withLock { current -> ScanSessionState? in
            switch (current.state, interrupted) {
            case (.running, true):
                current.state = .interrupted
            case (.interrupted, false):
                current.state = .running
            default:
                return nil
            }
            return current.state
        }
        if let newState {
            stateBroadcast.yield(newState)
        }
    }

    private func end(as endState: ScanSessionState) {
        let changed = store.withLock { current -> Bool in
            guard !current.state.isFinished else { return false }
            current.state = endState
            if endState == .discarded {
                current.planes.removeAll()
            }
            return true
        }
        guard changed else { return }
        session.pause()
        stateBroadcast.yield(endState)
        stateBroadcast.finish()
        frameBroadcast.finish()
    }

    // MARK: - ARSessionDelegate (runs on `delegateQueue`)

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard acceptsFrame(at: frame.timestamp) else { return }
        deliver(ScanFrame(frame, planes: planes))
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        updatePlanes(anchors.compactMap { ScanPlane($0) })
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        updatePlanes(anchors.compactMap { ScanPlane($0) })
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        removePlanes(anchors.map(\.identifier))
    }

    func session(_ session: ARSession, didFailWithError error: any Error) {
        fail(with: error)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        setInterrupted(true)
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        setInterrupted(false)
    }
}
