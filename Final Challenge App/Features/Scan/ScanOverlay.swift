import CoreGraphics
import simd
import MeasureKit

/// Where things go on the scan screen: a 3D spot's tag on the screen, a tap's point in the camera picture, and the
/// Finish Scan rule (A10-62, Sketch R03 with Amadeus's 11 Nov changes).
nonisolated enum ScanOverlay {
    /// Finish Scan rule (Amadeus, 11 Nov): exactly one subject, at least one camera and at least one studio light.
    static func canFinish(hasSubject: Bool, acceptedCameras: Int, acceptedLights: Int) -> Bool {
        if hasSubject && acceptedCameras >= 1 && acceptedLights >= 1 {
            return true
        } else {
            return false
        }
    }

    /// 3D spot → picture pixel (`DepthSampler.project`) → upright picture → screen.
    /// The sideways picture (width W, height H) is turned upright: pixel (u, v) becomes (H - v, u).
    /// The upright picture fills the screen from the centre, so its sides may be cut off.
    static func screenPoint(of spot: SIMD3<Float>, camera: CameraModel, screenSize: CGSize) -> CGPoint? {
        guard let point = unclippedScreenPoint(of: spot, camera: camera, screenSize: screenSize),
              point.x >= 0, point.x < screenSize.width, point.y >= 0, point.y < screenSize.height else { return nil }
        return point
    }

    /// The outline around a tapped item (Sketch UT Review T04): the screen box holding `points`, cut to the screen.
    /// Points behind the camera are left out; nil when fewer than two are in front or the box is off the screen.
    static func screenBox(of points: [SIMD3<Float>], camera: CameraModel, screenSize: CGSize) -> CGRect? {
        let projected = points.compactMap { unclippedScreenPoint(of: $0, camera: camera, screenSize: screenSize) }
        guard projected.count >= 2,
              let minX = projected.map(\.x).min(), let maxX = projected.map(\.x).max(),
              let minY = projected.map(\.y).min(), let maxY = projected.map(\.y).max() else { return nil }
        let box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .intersection(CGRect(origin: .zero, size: screenSize))
        return box.isNull || box.isEmpty ? nil : box
    }

    /// `screenPoint` without the on-screen check; nil only when the spot is behind the camera.
    private static func unclippedScreenPoint(of spot: SIMD3<Float>, camera: CameraModel,
                                             screenSize: CGSize) -> CGPoint? {
        guard let pixel = unclippedPixel(of: spot, camera: camera) else { return nil }
        let pictureHeight = CGFloat(camera.imageResolution.y)
        let upright = CGPoint(x: pictureHeight - CGFloat(pixel.y), y: CGFloat(pixel.x))
        let uprightSize = CGSize(width: pictureHeight, height: CGFloat(camera.imageResolution.x))
        let scale = max(screenSize.width / uprightSize.width, screenSize.height / uprightSize.height)
        return CGPoint(x: upright.x * scale + (screenSize.width - uprightSize.width * scale) / 2,
                       y: upright.y * scale + (screenSize.height - uprightSize.height * scale) / 2)
    }

    /// `DepthSampler.project` without its picture-bounds check, so a box can reach past the screen's edge.
    private static func unclippedPixel(of spot: SIMD3<Float>, camera: CameraModel) -> SIMD2<Float>? {
        let local = camera.cameraToWorld.inverse * SIMD4<Float>(spot, 1)
        let depth = -local.z
        guard depth >= DepthSampler.minProjectDepth else { return nil }
        let intrinsics = camera.intrinsics
        return SIMD2(intrinsics[0][0] * local.x / depth + intrinsics[2][0],
                     intrinsics[1][1] * -local.y / depth + intrinsics[2][1])
    }

    /// A tap on the screen → the point it touches in the camera picture, as fractions of the picture (0...1, top-left).
    /// The exact reverse of `screenPoint`. Nil when the tap is outside the screen.
    static func picturePoint(fromScreen tap: CGPoint, camera: CameraModel, screenSize: CGSize) -> CGPoint? {
        guard tap.x >= 0, tap.x < screenSize.width, tap.y >= 0, tap.y < screenSize.height else { return nil }
        let pictureHeight = CGFloat(camera.imageResolution.y)
        let pictureWidth = CGFloat(camera.imageResolution.x)
        let uprightSize = CGSize(width: pictureHeight, height: pictureWidth)
        let scale = max(screenSize.width / uprightSize.width, screenSize.height / uprightSize.height)
        let upright = CGPoint(x: (tap.x - (screenSize.width - uprightSize.width * scale) / 2) / scale,
                              y: (tap.y - (screenSize.height - uprightSize.height * scale) / 2) / scale)
        // Upright (x, y) is the sideways picture's (H - v, u).
        return CGPoint(x: upright.y / pictureWidth, y: (pictureHeight - upright.x) / pictureHeight)
    }
}
