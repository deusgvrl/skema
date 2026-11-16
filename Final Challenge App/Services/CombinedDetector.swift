import MeasureKit

/// Runs YOLOE (studio lighting) and Vision (cameras) on the same frame at the same time, and joins the results
/// (A10-90, cases D6–D8), then trims each mask by depth (cases D15, D16, D18).
/// It fills the same `EquipmentDetecting` slot, so tracking and the overlay don't change.
nonisolated struct CombinedDetector: EquipmentDetecting {
    let lights: any EquipmentDetecting
    let cameras: any EquipmentDetecting

    /// Both sides start together (`async let`), so a look takes about as long as the slower side.
    @concurrent
    func detect(in frame: ScanFrame) async throws -> [EquipmentDetection] {
        // Case D18: without depth the masks can't be trimmed, so the look finds nothing.
        guard let depth = frame.depth else { return [] }
        async let lightLook = Self.attempt { try await lights.detect(in: frame) }
        async let cameraLook = Self.attempt { try await cameras.detect(in: frame) }
        return Self.trimmed(try Self.join(lights: await lightLook, cameras: await cameraLook), depth: depth)
    }

    /// Cases D15–D16: each mask is cut down to its nearest depth group (`DepthGrouping`), so a wall behind a light
    /// or a person behind a camera is not part of the item. The same mask then feeds the screen and the measuring.
    static func trimmed(_ detections: [EquipmentDetection], depth: DepthFrame) -> [EquipmentDetection] {
        detections.map {
            EquipmentDetection(kind: $0.kind, confidence: $0.confidence,
                               mask: DepthGrouping.nearestGroup(in: $0.mask, depth: depth), isWeak: $0.isWeak)
        }
    }

    /// One side's look, with a failure kept as a value instead of thrown, so the other side's result isn't lost.
    private static func attempt(
        _ look: @Sendable () async throws -> [EquipmentDetection]
    ) async -> Result<[EquipmentDetection], any Error> {
        do {
            return .success(try await look())
        } catch {
            return .failure(error)
        }
    }

    /// Lights first, then cameras. When one side failed, the other side's results still come through (D7).
    /// When both failed, the look fails (D8), so the scan counts it as "nothing seen".
    static func join(lights: Result<[EquipmentDetection], any Error>,
                     cameras: Result<[EquipmentDetection], any Error>) throws -> [EquipmentDetection] {
        if case .failure(let error) = lights, case .failure = cameras {
            throw error
        }
        return ((try? lights.get()) ?? []) + ((try? cameras.get()) ?? [])
    }
}
