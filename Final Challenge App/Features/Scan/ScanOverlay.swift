import CoreGraphics
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
        guard let pixel = DepthSampler.project(spot, camera: camera) else { return nil }
        let pictureHeight = CGFloat(camera.imageResolution.y)
        let upright = CGPoint(x: pictureHeight - CGFloat(pixel.y), y: CGFloat(pixel.x))
        let uprightSize = CGSize(width: pictureHeight, height: CGFloat(camera.imageResolution.x))
        let scale = max(screenSize.width / uprightSize.width, screenSize.height / uprightSize.height)
        let point = CGPoint(x: upright.x * scale + (screenSize.width - uprightSize.width * scale) / 2,
                            y: upright.y * scale + (screenSize.height - uprightSize.height * scale) / 2)
        guard point.x >= 0, point.x < screenSize.width, point.y >= 0, point.y < screenSize.height else { return nil }
        return point
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
