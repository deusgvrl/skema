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
func near(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ tol: Float = 1e-4) -> Bool { simd_length(a - b) < tol }

/// Centimetres to metres. The written A10-42 cases use whole centimetres.
func cm(_ value: Float) -> Float { value / 100 }

/// Deterministic synthetic point sets for the A10-42 tests. Arguments are in centimetres; points come out in metres.
enum SyntheticEquipment {
    /// Points on a vertical line at (x, z) from `bottom` to `top`, `total` points in all.
    /// `capCount` of them sit exactly at `top` (a flat top face). Reason: the 98% percentile of evenly
    /// spread points lies a few cm under the real top by design, so a flat top lets tests check the top exactly.
    static func column(x: Float, z: Float, bottom: Float, top: Float, total: Int, capCount: Int = 5) -> [SIMD3<Float>] {
        let lineCount = total - capCount
        var points: [SIMD3<Float>] = []
        for i in 0..<lineCount {
            let t = lineCount > 1 ? Float(i) / Float(lineCount - 1) : 0
            points.append(SIMD3(cm(x), cm(bottom + (top - bottom) * t), cm(z)))
        }
        for _ in 0..<capCount { points.append(SIMD3(cm(x), cm(top), cm(z))) }
        return points
    }

    /// Three legs at 90, 210 and 330 degrees around (x, z), each a vertical line from 0 to `height`
    /// above `floor`, with the same number of points per leg, so the middle between them is exactly (x, z).
    static func tripodLegs(x: Float, z: Float, radius: Float, floor: Float = 0, height: Float, pointsPerLeg: Int) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        for degrees: Float in [90, 210, 330] {
            let angle = degrees * .pi / 180
            let legX = x + radius * cos(angle), legZ = z + radius * sin(angle)
            for i in 0..<pointsPerLeg {
                let t = Float(i) / Float(pointsPerLeg - 1)
                points.append(SIMD3(cm(legX), cm(floor + height * t), cm(legZ)))
            }
        }
        return points
    }

    /// The same points moved up or down by `dy` centimetres.
    static func shifted(_ points: [SIMD3<Float>], dy: Float) -> [SIMD3<Float>] {
        points.map { SIMD3($0.x, $0.y + cm(dy), $0.z) }
    }
}

/// A measured piece of equipment: base centre at (`baseX`, `baseZ`), top `topY` high. Arguments in centimetres.
func measuredCentres(baseX: Float, baseZ: Float, topY: Float = 180) -> EquipmentCentres {
    EquipmentCentres(
        status: .measured,
        baseCentre: SIMD2(cm(baseX), cm(baseZ)),
        topCentre: SIMD3(cm(baseX), cm(topY), cm(baseZ)))
}

/// A piece of equipment that could not be measured: no base centre and no top centre.
func notMeasuredCentres() -> EquipmentCentres {
    EquipmentCentres(status: .tooFewPoints, baseCentre: nil, topCentre: nil)
}
