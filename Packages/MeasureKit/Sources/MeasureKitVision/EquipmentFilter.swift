/// Which decoded rows become detections (A10-60). Rows come in after the confidence cutoff (`YOLOSegmentDecoder.rows`).
/// Order: known labels only → drop whole-frame boxes → one box per object within each label. No cap.
public enum EquipmentFilter {
    /// Trimmed and lowercased, so "Camera " and "camera" are the same label.
    public static func normalized(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// - Parameters:
    ///   - classNames: class index → label, from the model's metadata (several prompts can share a label).
    ///   - labels: the labels to keep, compared after `normalized`.
    ///   - maxAreaFraction: boxes covering more than this share of the frame (after clipping) are dropped.
    ///   - iouThreshold: within one label, a box overlapping a kept, higher-scoring box by IoU above this is dropped.
    ///     Boxes with different labels never remove each other (a camera inside a ring light stays).
    /// - Returns: kept rows, best first.
    public static func keep(_ rows: [YOLORow], classNames: [Int: String], labels: Set<String>,
                            maxAreaFraction: Float, iouThreshold: Float, inputSize: Float = 640) -> [YOLORow] {
        let wanted = Set(labels.map(normalized))
        func label(of row: YOLORow) -> String? {
            classNames[row.classIndex].map(normalized).flatMap { wanted.contains($0) ? $0 : nil }
        }
        let frameArea = inputSize * inputSize
        var kept: [(row: YOLORow, label: String)] = []
        for row in rows.sorted(by: { $0.confidence > $1.confidence }) {
            guard let name = label(of: row) else { continue }
            let width = max(0, min(row.x2, inputSize) - max(row.x1, 0))
            let height = max(0, min(row.y2, inputSize) - max(row.y1, 0))
            guard width * height <= maxAreaFraction * frameArea else { continue }
            if kept.contains(where: { $0.label == name && YOLOSegmentDecoder.iou($0.row, row) > iouThreshold }) { continue }
            kept.append((row, name))
        }
        return kept.map(\.row)
    }
}

extension YOLOSegmentDecoder {
    static func iou(_ a: YOLORow, _ b: YOLORow) -> Float {
        let width = max(0, min(a.x2, b.x2) - max(a.x1, b.x1))
        let height = max(0, min(a.y2, b.y2) - max(a.y1, b.y1))
        let overlap = width * height
        let union = (a.x2 - a.x1) * (a.y2 - a.y1) + (b.x2 - b.x1) * (b.y2 - b.y1) - overlap
        return union > 0 ? overlap / union : 0
    }

    /// The Ultralytics way (`ultralytics/utils/ops.py`, `process_mask` with upsample=True): mask logits at proto size,
    /// bilinear resize to `inputSize` x `inputSize` (align_corners = false, like PyTorch's `F.interpolate`),
    /// on where the logit > 0, then cut to the box with x1 <= x < x2 and y1 <= y < y2 (`crop_mask`).
    /// `protos` is [C, protoSize, protoSize], flat. Only pixels inside the box are computed.
    public static func upsampledMask(for row: YOLORow, protos: [Float], protoSize: Int = 160,
                                     inputSize: Int = 640) -> InstanceMask {
        let plane = protoSize * protoSize
        let channels = min(row.coefficients.count, protos.count / max(plane, 1))
        var logits = [Float](repeating: 0, count: plane)
        for c in 0..<channels {
            let weight = row.coefficients[c]
            for i in 0..<plane { logits[i] += weight * protos[c * plane + i] }
        }

        var pixels = [UInt8](repeating: 0, count: inputSize * inputSize)
        let xStart = max(0, Int(row.x1.rounded(.up))), xEnd = min(inputSize, Int(row.x2.rounded(.up)))
        let yStart = max(0, Int(row.y1.rounded(.up))), yEnd = min(inputSize, Int(row.y2.rounded(.up)))
        guard xStart < xEnd, yStart < yEnd, plane > 0 else {
            return InstanceMask(width: inputSize, height: inputSize, pixels: pixels)
        }
        let scale = Float(protoSize) / Float(inputSize)
        let last = protoSize - 1
        func source(_ i: Int) -> (low: Int, high: Int, t: Float) {
            let s = max(0, (Float(i) + 0.5) * scale - 0.5)
            let low = min(Int(s), last)
            return (low, min(low + 1, last), s - Float(low))
        }
        let columns = (xStart..<xEnd).map(source)
        for y in yStart..<yEnd {
            let (y0, y1, ty) = source(y)
            for (offset, (x0, x1, tx)) in columns.enumerated() {
                let top = logits[y0 * protoSize + x0] * (1 - tx) + logits[y0 * protoSize + x1] * tx
                let bottom = logits[y1 * protoSize + x0] * (1 - tx) + logits[y1 * protoSize + x1] * tx
                if top * (1 - ty) + bottom * ty > 0 { pixels[y * inputSize + xStart + offset] = 1 }
            }
        }
        return InstanceMask(width: inputSize, height: inputSize, pixels: pixels)
    }
}
