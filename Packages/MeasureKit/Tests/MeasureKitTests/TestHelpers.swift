import simd
@testable import MeasureKit

/// Camera with fx = fy = 100, principal point at the centre of a 200x100 image.
func makeCamera(pose: simd_float4x4 = matrix_identity_float4x4) -> CameraModel {
    let k = simd_float3x3(columns: (
        SIMD3<Float>(100, 0, 0),
        SIMD3<Float>(0, 100, 0),
        SIMD3<Float>(100, 50, 1)
    ))
    return CameraModel(intrinsics: k, imageResolution: SIMD2<Float>(200, 100), cameraToWorld: pose)
}

func makeFrame(width: Int = 20, height: Int = 10, depth: Float, confidence: UInt8 = 2) -> DepthFrame {
    DepthFrame(width: width, height: height,
               depth: [Float](repeating: depth, count: width * height),
               confidence: [UInt8](repeating: confidence, count: width * height))
}

func near(_ a: Float, _ b: Float, _ tol: Float = 1e-4) -> Bool { abs(a - b) < tol }
func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ tol: Float = 1e-4) -> Bool { simd_length(a - b) < tol }
