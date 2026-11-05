import CoreVideo
import simd

// Shared contract between the detector, the depth maths and the app.
// Owned by the main session. Agents read it; they don't change it.

/// A box in normalized image coordinates: origin top-left, x to the right, y down, values in 0...1.
/// Always relative to the camera's native (sensor) image: the same image as ARKit's
/// `capturedImage`, which `sceneDepth` is aligned to.
public struct NormalizedBox: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Which pixels belong to one object. Same frame as `NormalizedBox`: the native image,
/// origin top-left, row-major. Usually lower resolution than the image; scale by normalized position.
public struct InstanceMask: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// `width * height` values: 1 inside the object, 0 outside.
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

/// One labeled object from a detector.
public struct Detection: Equatable, Sendable {
    public let label: String
    public let confidence: Float
    /// Bounding box. With a mask, it is the mask's bounds.
    public let box: NormalizedBox
    /// The object's exact pixels, when the detector segments. Depth sampling prefers it over the box.
    public let mask: InstanceMask?

    public init(label: String, confidence: Float, box: NormalizedBox, mask: InstanceMask? = nil) {
        self.label = label
        self.confidence = confidence
        self.box = box
        self.mask = mask
    }
}

/// How the native image must be turned to look upright to a person.
/// Same meaning as `CGImagePropertyOrientation` (`.right` for the back camera held in portrait).
public enum ImageOrientation: Sendable {
    case up, down, left, right
}

/// Anything that finds labeled boxes in a camera image.
/// Phase 1: `VisionDetector`. Phase 2: a YOLO detector behind the same protocol.
public protocol ObjectDetector {
    /// Shown in the app and written to the CSV, so runs from different detectors can be compared.
    var name: String { get }
    /// Boxes come back in native-image coordinates (see `NormalizedBox`), whatever `orientation` is.
    func detect(in image: CVPixelBuffer, orientation: ImageOrientation) async throws -> [Detection]
}

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

/// What the PoC reports for one detected object. All lengths in metres, angles in degrees.
public struct ObjectMeasurement: Equatable, Sendable {
    public let detection: Detection
    /// World position (median of the object's depth points). Nil when there were too few points.
    public let position: SIMD3<Float>?
    /// Depth points used. Low counts mean the numbers are weak.
    public let pointCount: Int
    /// Straight-line distance to the subject. 0 for the subject itself.
    public let distanceToSubject: Float?
    /// Position height above the floor plane. Nil when no floor was found.
    public let heightAboveFloor: Float?
    /// Main axis vs vertical: 0 = upright, 90 = lying flat.
    public let tiltDegrees: Float?
    /// Angle on the floor between the main axis and the line to the subject, 0...90.
    /// Nil when the axis is near vertical (no horizontal direction to compare).
    public let aimOffsetDegrees: Float?

    public init(
        detection: Detection,
        position: SIMD3<Float>?,
        pointCount: Int,
        distanceToSubject: Float?,
        heightAboveFloor: Float?,
        tiltDegrees: Float?,
        aimOffsetDegrees: Float?
    ) {
        self.detection = detection
        self.position = position
        self.pointCount = pointCount
        self.distanceToSubject = distanceToSubject
        self.heightAboveFloor = heightAboveFloor
        self.tiltDegrees = tiltDegrees
        self.aimOffsetDegrees = aimOffsetDegrees
    }
}
