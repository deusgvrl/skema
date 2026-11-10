#if DEBUG
import CoreGraphics
import Foundation
import Observation

/// How many detections finished in the last second.
nonisolated struct DetectionRate {
    private var times: [TimeInterval] = []

    mutating func record(at time: TimeInterval) {
        times.append(time)
        times.removeAll { $0 <= time - 1 }
    }

    /// Detections that finished in (time - 1 s, time].
    func count(at time: TimeInterval) -> Int {
        times.filter { $0 > time - 1 && $0 <= time }.count
    }
}

/// State of the Debug-only detector test screen: the camera with masks, captions, speed and heat.
/// Frames are handled one at a time: the next frame waits until the current detection is done.
@Observable
final class DetectorDebugViewModel {
    private(set) var captions: [String] = []
    private(set) var lastMilliseconds: Double?
    private(set) var detectionsPerSecond = 0
    private(set) var thermalText = ""
    private(set) var errorText: String?
    /// The masks on a clear picture, upright, the size of the camera frame.
    private(set) var image: CGImage?
    /// The live scan session (nil in tests). The view shows its camera.
    let scanSession: ScanSession?

    private let detector: any EquipmentDetecting
    private let now: () -> TimeInterval
    private let thermalState: () -> ProcessInfo.ThermalState
    private let render: @Sendable (ScanFrame, [EquipmentDetection]) async -> CGImage?
    private var rate = DetectionRate()

    init(detector: any EquipmentDetecting,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         thermalState: @escaping () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState },
         render: @escaping @Sendable (ScanFrame, [EquipmentDetection]) async -> CGImage?,
         scanSession: ScanSession? = nil) {
        self.detector = detector
        self.scanSession = scanSession
        self.now = now
        self.thermalState = thermalState
        self.render = render
    }

    func run(frames: AsyncStream<ScanFrame>) async {
        for await frame in frames {
            let start = now()
            do {
                let detections = try await detector.detect(in: frame)
                let end = now()
                lastMilliseconds = (end - start) * 1000
                rate.record(at: end)
                detectionsPerSecond = rate.count(at: end)
                captions = detections.sorted { $0.confidence > $1.confidence }.map(Self.caption)
                errorText = nil
                image = await render(frame, detections)
            } catch {
                errorText = "Detection failed: \(error)"
            }
            thermalText = Self.text(for: thermalState())
        }
    }

    static func caption(_ detection: EquipmentDetection) -> String {
        let name = switch detection.kind {
        case .studioLighting: "studio lighting"
        case .camera: "Camera"
        }
        return "\(name) \(Int((detection.confidence * 100).rounded()))%"
    }

    static func text(for state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
#endif
