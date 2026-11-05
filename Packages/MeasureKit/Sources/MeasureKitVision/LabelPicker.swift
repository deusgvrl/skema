public enum LabelPicker {
    /// Highest-confidence classification whose identifier is in `targets` and >= `minConfidence`.
    public static func pick(_ classifications: [(identifier: String, confidence: Float)],
                            targets: Set<String>, minConfidence: Float) -> (label: String, confidence: Float)? {
        classifications
            .filter { targets.contains($0.identifier) && $0.confidence >= minConfidence }
            .max { $0.confidence < $1.confidence }
            .map { (label: $0.identifier, confidence: $0.confidence) }
    }
}
