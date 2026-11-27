import Foundation
import simd
@testable import MeasureKit

/// A pretend room made of boxes, rendered into LiDAR depth frames like ARKit's (27 Nov): the tests can then check what
/// a tap really picks out, with tables, stands, backdrops and people around the tapped item.
///
/// The camera is an iPhone's: a 1920 x 1440 picture with fx = fy = 1450 and a 256 x 192 depth map. A depth pixel is the
/// distance along the view (as `DepthFrame.depth`) to the nearest box its ray hits; no hit has no depth.
struct SyntheticScene {
    var boxes: [WorldBox]
    /// Up to this much (metres) is added to or taken from each depth, the same for the same pixel and `seed`.
    var noise: Float = 0.004
    /// Edges where the depth jumps get "flying" dots between the near and the far surface, as LiDAR gives.
    var flyingPixels = false

    static let imageSize = SIMD2<Float>(1920, 1440)
    static let focal: Float = 1450
    static let depthSize = (width: 256, height: 192)

    /// A camera at `position` looking at `target`, upright.
    static func camera(at position: SIMD3<Float>, lookingAt target: SIMD3<Float>) -> CameraModel {
        let forward = simd_normalize(target - position)
        let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
        let up = simd_cross(right, forward)
        let pose = simd_float4x4(columns: (SIMD4(right, 0), SIMD4(up, 0), SIMD4(-forward, 0), SIMD4(position, 1)))
        let intrinsics = simd_float3x3(columns: (SIMD3(focal, 0, 0), SIMD3(0, focal, 0),
                                                 SIMD3(imageSize.x / 2, imageSize.y / 2, 1)))
        return CameraModel(intrinsics: intrinsics, imageResolution: imageSize, cameraToWorld: pose)
    }

    /// Cameras on an arc around `target`, `distance` away on the floor and `height` up, at each of `degrees`
    /// (0 = looking along -z from +z).
    static func walk(around target: SIMD3<Float>, distance: Float, height: Float, degrees: [Float]) -> [CameraModel] {
        degrees.map { angle in
            let radians = angle * .pi / 180
            let position = SIMD3(target.x + distance * sin(radians), height, target.z + distance * cos(radians))
            return camera(at: position, lookingAt: target)
        }
    }

    /// The depth frame `camera` sees. `drift` moves the whole room, as ARKit's tracking slowly corrects itself.
    func render(from camera: CameraModel, drift: SIMD3<Float> = .zero, seed: UInt32 = 0) -> DepthFrame {
        let (width, height) = Self.depthSize
        let scale = Self.imageSize / SIMD2(Float(width), Float(height))
        let rotation = simd_float3x3(SIMD3(camera.cameraToWorld.columns.0.x, camera.cameraToWorld.columns.0.y,
                                           camera.cameraToWorld.columns.0.z),
                                     SIMD3(camera.cameraToWorld.columns.1.x, camera.cameraToWorld.columns.1.y,
                                           camera.cameraToWorld.columns.1.z),
                                     SIMD3(camera.cameraToWorld.columns.2.x, camera.cameraToWorld.columns.2.y,
                                           camera.cameraToWorld.columns.2.z))
        let column3 = camera.cameraToWorld.columns.3
        let origin = SIMD3(column3.x, column3.y, column3.z) - drift
        var depths = [Float](repeating: 0, count: width * height)
        var confidences = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                let pixel = (SIMD2(Float(column), Float(row)) + 0.5) * scale
                // Along this direction one unit forward is one metre of view depth, so the hit distance is the depth.
                let direction = rotation * SIMD3((pixel.x - Self.imageSize.x / 2) / Self.focal,
                                                 -(pixel.y - Self.imageSize.y / 2) / Self.focal, -1)
                var nearest = Float.greatestFiniteMagnitude
                for box in boxes {
                    if let distance = Self.hit(box, from: origin, along: direction), distance < nearest {
                        nearest = distance
                    }
                }
                guard nearest < .greatestFiniteMagnitude else { continue }
                let hit = nearest
                let index = row * width + column
                depths[index] = hit + noise * Self.noise(row, column, seed)
                confidences[index] = 2
            }
        }
        if flyingPixels { addFlyingPixels(to: &depths, width: width, height: height, seed: seed) }
        return DepthFrame(width: width, height: height, depth: depths, confidence: confidences)
    }

    /// Where a tap at the picture spot of `target` lands, as the app finds it (`DepthSampler.nearestPoint`).
    func tap(at target: SIMD3<Float>, camera: CameraModel) -> SIMD3<Float>? {
        guard let pixel = DepthSampler.project(target, camera: camera) else { return nil }
        return DepthSampler.nearestPoint(toNormalized: pixel / camera.imageResolution, depth: render(from: camera),
                                         camera: camera)
    }

    // MARK: Building blocks

    /// The distance along the ray to the box, or nil when it misses (slab test).
    private static func hit(_ box: WorldBox, from origin: SIMD3<Float>, along direction: SIMD3<Float>) -> Float? {
        var near: Float = 0.05, far = Float.greatestFiniteMagnitude
        for axis in 0..<3 {
            if abs(direction[axis]) < 1e-9 {
                if origin[axis] < box.min[axis] || origin[axis] > box.max[axis] { return nil }
                continue
            }
            let first = (box.min[axis] - origin[axis]) / direction[axis]
            let second = (box.max[axis] - origin[axis]) / direction[axis]
            near = max(near, min(first, second))
            far = min(far, max(first, second))
            if near > far { return nil }
        }
        return near
    }

    /// A number from -1 to 1 that is always the same for the same pixel and seed.
    private static func noise(_ row: Int, _ column: Int, _ seed: UInt32) -> Float {
        var value = UInt32(truncatingIfNeeded: row &* 73_856_093) ^ UInt32(truncatingIfNeeded: column &* 19_349_663)
        value ^= seed &* 83_492_791
        value = (value ^ (value >> 13)) &* 1_274_126_177
        value ^= value >> 16
        return Float(value % 20_001) / 10_000 - 1
    }

    /// Half of the pixels next to a jump of more than 10 cm get a depth part way to the other side.
    private func addFlyingPixels(to depths: inout [Float], width: Int, height: Int, seed: UInt32) {
        let original = depths
        for row in 0..<height {
            for column in 0..<width where original[row * width + column] > 0 {
                let here = original[row * width + column]
                let neighbours = [(row, column + 1), (row + 1, column), (row, column - 1), (row - 1, column)]
                    .filter { $0.0 >= 0 && $0.0 < height && $0.1 >= 0 && $0.1 < width }
                    .map { original[$0.0 * width + $0.1] }
                guard let other = neighbours.first(where: { $0 > 0 && abs($0 - here) > 0.10 }) else { continue }
                let pick = Self.noise(row, column, seed &+ 7)
                guard pick > 0 else { continue }
                depths[row * width + column] = here + (other - here) * (0.25 + pick * 0.5)
            }
        }
    }
}

extension WorldBox {
    /// The box grown by `margin` on every side.
    func grown(by margin: Float) -> WorldBox {
        WorldBox(min: min - SIMD3(repeating: margin), max: max + SIMD3(repeating: margin))
    }

    /// True when `other` lies wholly inside this box.
    func holds(_ other: WorldBox) -> Bool {
        all(other.min .>= min) && all(other.max .<= max)
    }
}
