import Foundation
import MeasureKit
import MeasureKitVision
import simd
import Testing
@testable import Final_Challenge_App

/// Raw-data logger: what the detectors looked at but did not keep, and each mask before the depth trim.
@Suite("Raw-data candidates and untrimmed masks")
struct RawCandidateTests {
    private func row(_ confidence: Float, classIndex: Int) -> YOLORow {
        YOLORow(x1: 64, y1: 128, x2: 320, y2: 448, confidence: confidence, classIndex: classIndex, coefficients: [])
    }

    @Test("A YOLOE light under the 35% weak line is logged as a candidate that was not kept")
    func lightUnderTheCutoffIsLogged() {
        let names = [0: "studio lighting", 1: "camera"]
        let found = EquipmentDetector.candidates(
            from: [row(0.32, classIndex: 0), row(0.70, classIndex: 0), row(0.90, classIndex: 1)], classNames: names)

        #expect(found.map(\.label) == ["camera", "studio lighting", "studio lighting"])   // best first
        #expect(found.map(\.kept) == [false, true, false])   // YOLOE's camera is dropped; 32% is under the weak line
        #expect(found[2].confidence == 0.32)
        #expect(found[2].box == [0.1, 0.2, 0.4, 0.5])
        #expect(found.allSatisfy { $0.source == "yoloe" })
    }

    @Test("A Vision blob is logged with its camera score and its best label")
    func visionBlobIsLogged() {
        let blob = CameraDetector.candidate(box: [0, 0, 1, 1], classifications: [("tripod", 0.8), ("camera", 0.4)])
        #expect(blob.source == "vision")
        #expect(blob.confidence == 0.4)
        #expect(!blob.kept)
        #expect(blob.topLabel == "tripod")
        #expect(blob.topConfidence == 0.8)

        let unlisted = CameraDetector.candidate(box: [0, 0, 1, 1], classifications: [("lamp", 0.9)])
        #expect(unlisted.confidence == 0)
        #expect(CameraDetector.candidate(box: [0, 0, 1, 1], classifications: [("camera", 0.6)]).kept)
    }

    @Test("The store hands a look's candidates over once")
    func storeHandsOverOnce() {
        let store = RawCandidateStore()
        let one = CameraDetector.candidate(box: [0, 0, 1, 1], classifications: [("camera", 0.7)])
        store.record([one], at: 1.5)
        store.record([one], at: 1.5)

        #expect(store.take(at: 2.0).isEmpty)
        #expect(store.take(at: 1.5) == [one, one])
        #expect(store.take(at: 1.5).isEmpty)
    }

    @Test("A trimmed detection remembers its mask from before the trim, and the log saves both")
    func untrimmedMaskIsLogged() async throws {
        let wide = InstanceMask(width: 4, height: 1, pixels: [1, 1, 1, 1])
        let depth = DepthFrame(width: 4, height: 1, depth: [1.5, 1.5, 2, 2], confidence: [2, 2, 2, 2])
        let blob = EquipmentDetection(kind: .camera, confidence: 0.7, mask: wide)

        let trimmed = try #require(CombinedDetector.trimmed([blob], depth: depth).first)
        #expect(trimmed.mask.pixels == [1, 1, 0, 0])
        #expect(trimmed.untrimmedMask == wide)

        let request = RawLookSampler.Request(
            detections: [trimmed], sightings: [], joinedIDs: [], items: [],
            frame: try makeScanFrame(timestamp: 0, depth: depth), look: 0, savesPoints: false, samplesRoom: false,
            candidates: [CameraDetector.candidate(box: [0, 0, 1, 1], classifications: [("camera", 0.7)])])
        let sample = await RawLookSampler.sample(request)

        #expect(sample.detections.first?.depthMask?.runs == [0, 2, 2])
        #expect(sample.detections.first?.untrimmedDepthMask?.runs == [0, 4])
        #expect(sample.candidates.count == 1)
    }
}
