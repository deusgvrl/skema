import Foundation

/// One thing a detector looked at in a look, kept or not (raw-data logger only).
/// It shows why something was not detected: scored under the cutoff, had another label, or was never found.
nonisolated struct RawCandidate: Codable, Equatable, Sendable {
    /// "yoloe" or "vision".
    let source: String
    /// YOLOE: the row's label. Vision: always "camera" (the one label asked for).
    let label: String
    /// YOLOE: the row's confidence. Vision: the classifier's "camera" score for this blob (0 when not listed).
    let confidence: Float
    /// x, y, width, height from 0 to 1 in the upright picture, top-left origin.
    let box: [Float]
    /// True when it passed the label and cutoff rules (YOLOE's overlap and size rules are not checked here).
    let kept: Bool
    /// Vision only: the classifier's best label for the blob and its score.
    var topLabel: String?
    var topConfidence: Float?
}

/// Holds each look's candidates until the scan screen logs that look. Detectors run off the main actor,
/// so a lock guards it. Keyed by the frame's timestamp.
nonisolated final class RawCandidateStore: @unchecked Sendable {
    static let shared = RawCandidateStore()
    /// Looks that were never collected are dropped once this many newer ones wait.
    static let maxWaitingLooks = 8

    private let lock = NSLock()
    private var waiting: [Double: [RawCandidate]] = [:]

    func record(_ candidates: [RawCandidate], at timestamp: Double) {
        lock.withLock {
            waiting[timestamp, default: []] += candidates
            while waiting.count > Self.maxWaitingLooks, let oldest = waiting.keys.min() {
                waiting[oldest] = nil
            }
        }
    }

    /// The candidates recorded for the look at `timestamp`, removed from the store.
    func take(at timestamp: Double) -> [RawCandidate] {
        lock.withLock { waiting.removeValue(forKey: timestamp) ?? [] }
    }
}
