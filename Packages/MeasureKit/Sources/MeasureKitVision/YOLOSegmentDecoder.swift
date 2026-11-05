import MeasureKit

public struct YOLORow: Equatable, Sendable {
    public let x1, y1, x2, y2: Float
    public let confidence: Float
    public let classIndex: Int
    public let coefficients: [Float]

    public init(x1: Float, y1: Float, x2: Float, y2: Float, confidence: Float, classIndex: Int, coefficients: [Float]) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
        self.confidence = confidence; self.classIndex = classIndex; self.coefficients = coefficients
    }
}

public enum YOLOSegmentDecoder {
    /// Floats per output row: 4 box + conf + class + 32 mask coefficients.
    static let rowLength = 38

    public static func rows(output: [Float], count: Int, minConfidence: Float) -> [YOLORow] {
        guard output.count >= count * rowLength else { return [] }
        var rows: [YOLORow] = []
        for i in 0..<count {
            let o = i * rowLength
            let confidence = output[o + 4]
            guard confidence >= minConfidence else { continue }
            rows.append(YOLORow(x1: output[o], y1: output[o + 1], x2: output[o + 2], y2: output[o + 3],
                                confidence: confidence, classIndex: Int(output[o + 5]),
                                coefficients: Array(output[(o + 6)..<(o + rowLength)])))
        }
        return rows
    }
    /// `protos` is [C, protoSize, protoSize], flat. C is the number of coefficients of the row.
    /// A pixel is on when sigmoid(coefficients . protos) > 0.5, which is the same as the logit being > 0,
    /// and its index lies inside the row's box scaled to proto pixels: x1s <= x < x2s (the Ultralytics crop rule).
    public static func mask(for row: YOLORow, protos: [Float], protoSize: Int = 160, inputSize: Float = 640) -> InstanceMask {
        let plane = protoSize * protoSize
        var pixels = [UInt8](repeating: 0, count: plane)
        let channels = min(row.coefficients.count, protos.count / max(plane, 1))
        let scale = Float(protoSize) / inputSize
        let x1 = row.x1 * scale, x2 = row.x2 * scale, y1 = row.y1 * scale, y2 = row.y2 * scale
        let xStart = max(0, Int(x1.rounded(.up))), xEnd = min(protoSize, Int(x2.rounded(.up)))
        let yStart = max(0, Int(y1.rounded(.up))), yEnd = min(protoSize, Int(y2.rounded(.up)))
        guard xStart < xEnd, yStart < yEnd else { return InstanceMask(width: protoSize, height: protoSize, pixels: pixels) }
        for y in yStart..<yEnd {
            for x in xStart..<xEnd {
                var logit: Float = 0
                for c in 0..<channels { logit += row.coefficients[c] * protos[c * plane + y * protoSize + x] }
                if logit > 0 { pixels[y * protoSize + x] = 1 }
            }
        }
        return InstanceMask(width: protoSize, height: protoSize, pixels: pixels)
    }
    /// Parses a Python dict repr like "{0: 'person', 9: 'traffic light'}". Python's repr uses double quotes
    /// for a name that contains an apostrophe, so both quote kinds are accepted. Anything else is skipped.
    public static func classNames(fromMetadata names: String) -> [Int: String] {
        var result: [Int: String] = [:]
        let chars = Array(names)
        var i = 0
        while i < chars.count {
            guard chars[i].isNumber else { i += 1; continue }
            var j = i
            while j < chars.count, chars[j].isNumber { j += 1 }
            let key = Int(String(chars[i..<j]))
            while j < chars.count, chars[j] == " " { j += 1 }
            guard let key, j < chars.count, chars[j] == ":" else { i = j; continue }
            j += 1
            while j < chars.count, chars[j] == " " { j += 1 }
            guard j < chars.count, chars[j] == "'" || chars[j] == "\"" else { i = j; continue }
            let quote = chars[j]
            let start = j + 1
            var end = start
            while end < chars.count, chars[end] != quote { end += 1 }
            guard end < chars.count else { break }
            result[key] = String(chars[start..<end])
            i = end + 1
        }
        return result
    }
}
