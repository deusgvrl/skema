import simd

// Shared contract between the depth maths and the app.

/// One LiDAR depth frame, copied out of `ARDepthData` so the maths runs without ARKit.
public struct DepthFrame: Sendable {
    public let width: Int
    public let height: Int
    /// Metres from the camera plane, row-major, `width * height` values.
    public let depth: [Float]
    /// `ARConfidenceLevel` raw values per pixel: 0 low, 1 medium, 2 high.
    public let confidence: [UInt8]

    public init(width: Int, height: Int, depth: [Float], confidence: [UInt8]) {
        self.width = width
        self.height = height
        self.depth = depth
        self.confidence = confidence
    }
}

/// Camera state for the frame, copied out of `ARCamera`.
public struct CameraModel: Sendable {
    /// `ARCamera.intrinsics`, valid for `imageResolution` (fx, fy on the diagonal, cx, cy in the third column).
    public let intrinsics: simd_float3x3
    /// `capturedImage` width and height in pixels.
    public let imageResolution: SIMD2<Float>
    /// `ARCamera.transform`: camera space (x right, y up, z backward) to world space (y up, gravity-aligned).
    public let cameraToWorld: simd_float4x4

    public init(intrinsics: simd_float3x3, imageResolution: SIMD2<Float>, cameraToWorld: simd_float4x4) {
        self.intrinsics = intrinsics
        self.imageResolution = imageResolution
        self.cameraToWorld = cameraToWorld
    }
}

/// How the top centre of a piece of equipment is found.
public enum CentreRule: Sendable {
    /// The top centre is the highest part of the points (a thin slice under the top height). Cameras, for now.
    case topPoint
    /// The top centre is the middle of the points in 3D: the centre of their extents, with a few stray points trimmed.
    /// A light: the middle of the head. Its base centre is that point straight down.
    case middle
}

/// Why a piece of equipment has, or has no, measured values. Precedence when several apply:
/// `outOfRange`, then `tooFewPoints`, then `measured`.
public enum MeasurementStatus: String, Codable, Sendable {
    case measured, tooFewPoints, outOfRange
}

/// Base centre and top centre of one piece of equipment (the subject included), or the reason they could not be computed.
public struct EquipmentCentres: Equatable, Sendable {
    public let status: MeasurementStatus
    /// Where the equipment stands: x and z on the floor, metres. Nil unless `status == .measured`.
    public let baseCentre: SIMD2<Float>?
    /// The top of the whole equipment including its modifier: x, y, z, metres. Nil unless `status == .measured`.
    public let topCentre: SIMD3<Float>?

    public init(status: MeasurementStatus, baseCentre: SIMD2<Float>?, topCentre: SIMD3<Float>?) {
        self.status = status
        self.baseCentre = baseCentre
        self.topCentre = topCentre
    }
}

/// What a scan found for one piece of equipment (the subject included): its status and, when measured, its values.
/// Lengths in metres. Nil means "Not measured". A10-22 saves it and A10-23 shows it.
public struct EquipmentResult: Equatable, Sendable {
    public let status: MeasurementStatus
    /// Distance on the floor from the subject's base centre to this equipment's base centre.
    public let distanceToSubject: Float?
    /// Height from the floor to this equipment's top centre.
    public let height: Float?
    /// This equipment's base centre minus the subject's base centre: x and z on the floor.
    public let floorOffset: SIMD2<Float>?
    /// How many points the equipment has.
    public let pointCount: Int

    public init(status: MeasurementStatus, distanceToSubject: Float?, height: Float?,
                floorOffset: SIMD2<Float>?, pointCount: Int) {
        self.status = status
        self.distanceToSubject = distanceToSubject
        self.height = height
        self.floorOffset = floorOffset
        self.pointCount = pointCount
    }
}
