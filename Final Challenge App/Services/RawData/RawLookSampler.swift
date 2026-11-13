import CoreVideo
import MeasureKit
import MeasureKitVision

/// What one look adds to the raw-data log, before the log's budget and room thinning.
nonisolated struct RawLookSample: Sendable {
    let detections: [RawDetection]
    let rawPoints: [RawMaskPoint]
    let keptPoints: [RawKeptPoint]
    /// Room candidates (every `roomPixelStride`-th depth pixel); empty when the room was not sampled.
    let roomPoints: [(world: SIMD3<Float>, rgb: SIMD3<UInt8>)]
    let sampledRoom: Bool
}

/// Turns one look into raw records: each detection's mask points (unfiltered and kept), its sighting and item id,
/// and the room points. Runs off the main actor so the scan stays smooth.
nonisolated enum RawLookSampler {
    /// Each detection saves at most this many raw points and this many kept points (evenly thinned).
    static let maxPointsPerDetection = 3000
    /// Room points take every 2nd depth pixel in each direction, like the old room scan.
    static let roomPixelStride = 2

    struct Request: Sendable {
        let detections: [EquipmentDetection]
        /// The tracker's latest sightings, in detection order (`EquipmentSightings.make`).
        let sightings: [SightedDetection]
        /// The item id each sighting joined (`ObjectMap.update`), same order as `sightings`.
        let joinedIDs: [Int]
        /// Every tracked item after this look's update.
        let items: [TrackedItem]
        let frame: ScanFrame
        let look: Int
        let savesPoints: Bool
        let samplesRoom: Bool
    }

    @concurrent static func sample(_ request: Request) async -> RawLookSample {
        let frame = request.frame
        let matches = matchSightings(request.detections, sightings: request.sightings, joinedIDs: request.joinedIDs)
        var detections: [RawDetection] = []
        var rawPoints: [RawMaskPoint] = []
        var keptPoints: [RawKeptPoint] = []
        for (index, found) in request.detections.enumerated() {
            let match = matches[index]
            let itemID = Int32(match?.itemID ?? -1)
            let tag = RawTag(look: Int32(request.look), item: itemID, detection: Int16(clamping: index))
            var raw: [RawMaskPoint] = []
            var kept: [SIMD3<Float>] = []
            var grid: RawMaskGrid?
            if let depth = frame.depth {
                let unfiltered = maskPoints(in: found.mask, depth: depth, camera: frame.camera, tag: tag)
                raw = unfiltered.points
                grid = unfiltered.grid
                kept = DepthSampler.worldPoints(in: found.mask, depth: depth, camera: frame.camera,
                                                maxRange: DepthSampler.maxRange)
            }
            let savedRaw = request.savesPoints ? thinned(raw, to: maxPointsPerDetection) : []
            let savedKept = request.savesPoints ? thinned(kept, to: maxPointsPerDetection) : []
            rawPoints += savedRaw
            keptPoints += savedKept.map {
                RawKeptPoint(position: $0, look: tag.look, item: tag.item, detection: tag.detection)
            }
            detections.append(RawDetection(
                index: index, kind: kindName(found.kind), confidence: found.confidence,
                maskBounds: MaskMapping.bounds(of: found.mask).map(RawBox.init),
                maskWidth: found.mask.width, maskHeight: found.mask.height, depthMask: grid,
                rawPointCount: raw.count, rawPointsSaved: savedRaw.count,
                keptPointCount: kept.count, keptPointsSaved: savedKept.count, sighting: match))
        }
        var room: [(world: SIMD3<Float>, rgb: SIMD3<UInt8>)] = []
        if request.samplesRoom, let depth = frame.depth {
            let points = DepthSampler.scanPoints(depth: depth, camera: frame.camera, stride: roomPixelStride)
            let colours = PictureColours.colours(at: points.map(\.uv), in: frame.image)
            room = zip(points, colours).map { (world: $0.world, rgb: $1) }
        }
        return RawLookSample(detections: detections, rawPoints: rawPoints, keptPoints: keptPoints,
                             roomPoints: room, sampledRoom: request.samplesRoom)
    }

    /// The sighting each detection made, with the item id it joined; nil for a detection that made none.
    /// Sightings keep the detections' order and carry the same mask, so one pass pairs them.
    static func matchSightings(_ detections: [EquipmentDetection], sightings: [SightedDetection],
                               joinedIDs: [Int]) -> [RawSighting?] {
        var next = 0
        return detections.map { found in
            guard next < sightings.count, next < joinedIDs.count, sightings[next].mask == found.mask else { return nil }
            let seen = sightings[next].sighting
            defer { next += 1 }
            return RawSighting(label: seen.label, confidence: seen.confidence, position: seen.position,
                               axis: seen.axis, pointCount: seen.pointCount, itemID: joinedIDs[next])
        }
    }

    /// Every depth pixel whose centre falls on a mask pixel (no erosion), with any confidence and range, as long as
    /// its depth is finite and above 0. Same pixel mapping as `DepthSampler.worldPoints(in: mask, …)`.
    /// Also returns the mask on the depth grid, run-length encoded.
    static func maskPoints(in mask: InstanceMask, depth: DepthFrame, camera: CameraModel,
                           tag: RawTag) -> (points: [RawMaskPoint], grid: RawMaskGrid?) {
        guard depth.width > 0, depth.height > 0, mask.width > 0, mask.height > 0,
              mask.pixels.count == mask.width * mask.height,
              depth.depth.count == depth.width * depth.height,
              depth.confidence.count == depth.depth.count else { return ([], nil) }
        let scaleU = camera.imageResolution.x / Float(depth.width)
        let scaleV = camera.imageResolution.y / Float(depth.height)
        var points: [RawMaskPoint] = []
        var runs: [Int] = []
        var current: UInt8 = 0
        var length = 0
        for row in 0..<depth.height {
            let maskRow = min(mask.height - 1, Int((Float(row) + 0.5) / Float(depth.height) * Float(mask.height)))
            for column in 0..<depth.width {
                let maskColumn = min(mask.width - 1,
                                     Int((Float(column) + 0.5) / Float(depth.width) * Float(mask.width)))
                let inside: UInt8 = mask.pixels[maskRow * mask.width + maskColumn] != 0 ? 1 : 0
                if inside == current {
                    length += 1
                } else {
                    runs.append(length)
                    current = inside
                    length = 1
                }
                guard inside == 1 else { continue }
                let index = row * depth.width + column
                let metres = depth.depth[index]
                guard metres.isFinite, metres > 0 else { continue }
                let pixel = SIMD2<Float>((Float(column) + 0.5) * scaleU, (Float(row) + 0.5) * scaleV)
                points.append(RawMaskPoint(
                    position: DepthSampler.unproject(pixel: pixel, depth: metres, camera: camera),
                    look: tag.look, item: tag.item, detection: tag.detection,
                    confidence: depth.confidence[index], depth: metres,
                    column: UInt16(clamping: column), row: UInt16(clamping: row)))
            }
        }
        runs.append(length)
        return (points, RawMaskGrid(width: depth.width, height: depth.height, runs: runs))
    }

    /// At most `limit` values, evenly spread over `values` (every n-th), first value kept.
    static func thinned<Value>(_ values: [Value], to limit: Int) -> [Value] {
        guard limit > 0 else { return [] }
        guard values.count > limit else { return values }
        let step = Double(values.count) / Double(limit)
        return (0..<limit).map { values[Int(Double($0) * step)] }
    }

    static func kindName(_ kind: EquipmentKind) -> String {
        switch kind {
        case .studioLighting: "studioLighting"
        case .camera: "camera"
        }
    }
}

/// Colours from ARKit's camera picture (YCbCr 4:2:0, two planes). Any other picture gives grey.
nonisolated enum PictureColours {
    static let grey = SIMD3<UInt8>(128, 128, 128)

    /// The colour at each normalized spot (fractions of the native picture, top-left origin).
    static func colours(at spots: [SIMD2<Float>], in image: CVPixelBuffer) -> [SIMD3<UInt8>] {
        let format = CVPixelBufferGetPixelFormatType(image)
        guard format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
              CVPixelBufferGetPlaneCount(image) == 2 else {
            return [SIMD3<UInt8>](repeating: grey, count: spots.count)
        }
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        guard let lumaBase = CVPixelBufferGetBaseAddressOfPlane(image, 0),
              let chromaBase = CVPixelBufferGetBaseAddressOfPlane(image, 1) else {
            return [SIMD3<UInt8>](repeating: grey, count: spots.count)
        }
        let luma = lumaBase.assumingMemoryBound(to: UInt8.self)
        let chroma = chromaBase.assumingMemoryBound(to: UInt8.self)
        let lumaWidth = CVPixelBufferGetWidthOfPlane(image, 0), lumaHeight = CVPixelBufferGetHeightOfPlane(image, 0)
        let chromaWidth = CVPixelBufferGetWidthOfPlane(image, 1)
        let chromaHeight = CVPixelBufferGetHeightOfPlane(image, 1)
        let lumaRow = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
        let chromaRow = CVPixelBufferGetBytesPerRowOfPlane(image, 1)
        return spots.map { spot in
            let column = min(lumaWidth - 1, max(0, Int(spot.x * Float(lumaWidth))))
            let row = min(lumaHeight - 1, max(0, Int(spot.y * Float(lumaHeight))))
            let chromaColumn = min(chromaWidth - 1, column / 2), chromaLine = min(chromaHeight - 1, row / 2)
            let chromaIndex = chromaLine * chromaRow + chromaColumn * 2
            return ColorConversion.rgb(y: luma[row * lumaRow + column],
                                       cb: chroma[chromaIndex], cr: chroma[chromaIndex + 1])
        }
    }
}
