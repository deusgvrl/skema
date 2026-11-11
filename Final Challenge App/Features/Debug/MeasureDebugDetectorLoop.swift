#if DEBUG
import CoreGraphics
import Foundation
import MeasureKit
import Observation

/// Runs A10-60's `EquipmentDetector` on the newest frame about three times a second and hands what it finds to the
/// engine (A10-41). The model is large and warm, so it runs slowly and only while the Detector switch is on.
@Observable
final class MeasureDebugDetectorLoop {
    /// Time between two detections, so the model does not run on every frame.
    private static let pause: Duration = .milliseconds(330)

    var statusText = "Detector: off"
    /// What the detector found in the newest frame, and how the native camera image lands on the screen
    /// (for the overlay).
    var detections: [MeasureDebugDetection] = []
    var imageToView = CGAffineTransform.identity

    @ObservationIgnored private let engine: MeasureDebugEngine
    @ObservationIgnored private let displayTransform: () -> CGAffineTransform?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(engine: MeasureDebugEngine, displayTransform: @escaping () -> CGAffineTransform?) {
        self.engine = engine
        self.displayTransform = displayTransform
    }

    func setEnabled(_ enabled: Bool) {
        task?.cancel()
        task = nil
        detections = []
        guard enabled else {
            statusText = "Detector: off"
            return
        }
        task = Task { [weak self] in
            await self?.run()
        }
    }

    func stop() {
        setEnabled(false)
    }

    private func run() async {
        statusText = "Detector: loading the model"
        let detector: EquipmentDetector
        do {
            // Loading the 94 MB model takes a while, so it is done away from the main thread.
            detector = try await Task.detached { try EquipmentDetector() }.value
        } catch {
            statusText = "Detector: the model could not be loaded (\(error))"
            return
        }
        var lastTimestamp: TimeInterval?
        while !Task.isCancelled {
            if let frame = await engine.newestFrame(), frame.timestamp != lastTimestamp {
                lastTimestamp = frame.timestamp
                await detect(with: detector, in: frame)
            }
            try? await Task.sleep(for: Self.pause)
        }
    }

    private func detect(with detector: EquipmentDetector, in frame: ScanFrame) async {
        let started = ContinuousClock.now
        do {
            let detections = try await detector.detect(in: frame)
            let shown = await engine.ingestDetections(detections, from: frame)
            let milliseconds = Self.milliseconds(started.duration(to: .now))
            let used = shown.filter { $0.itemName != nil }.count
            statusText = String(
                format: "Detector: running, %d found, %d used, %.0f ms", detections.count, used, milliseconds
            )
            imageToView = displayTransform() ?? imageToView
            self.detections = shown
        } catch {
            statusText = "Detector: \(error)"
        }
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }
}
#endif
