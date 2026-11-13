/// Runs YOLOE (studio lighting) and Vision (cameras) on the same frame at the same time, and joins the results
/// (A10-90, cases D6–D8). It fills the same `EquipmentDetecting` slot, so tracking and the overlay don't change.
nonisolated struct CombinedDetector: EquipmentDetecting {
    let lights: any EquipmentDetecting
    let cameras: any EquipmentDetecting

    /// Both sides start together (`async let`), so a look takes about as long as the slower side.
    @concurrent
    func detect(in frame: ScanFrame) async throws -> [EquipmentDetection] {
        async let lightLook = Self.attempt { try await lights.detect(in: frame) }
        async let cameraLook = Self.attempt { try await cameras.detect(in: frame) }
        return try Self.join(lights: await lightLook, cameras: await cameraLook)
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
