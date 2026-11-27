import Foundation
import Testing
import simd
@testable import MeasureKit

// Tighter LiDAR boxes (27 Nov): pretend rooms (`SyntheticScene`) where today's scan picks up the table, a backdrop, a
// tripod or a person with the tapped item. Each test taps like the app, walks around, and checks the box drawn on
// screen and what the item is measured at against the truth, within 3 cm.

private let floorBox = WorldBox(min: SIMD3(-6, -0.05, -8), max: SIMD3(6, 0, 4))
private let tolerance: Float = 0.03

/// What one scan of one tapped item gave.
private struct SceneScan {
    var measurements = ScanMeasurements()
    let id = UUID()
    /// The outline after each frame.
    var outlines: [WorldBox?] = []

    var outline: WorldBox? { measurements.outline(for: id) }
    var height: Float? { measurements.results(subject: UUID(), floorY: 0)[id]?.height }
    var centres: EquipmentCentres? { measurements.centres(for: id, subject: id) }

    /// Taps `target` as the first camera sees it, then takes one frame per camera. `scenes` gives each frame its
    /// room (the same room when there is one), `drift` how far ARKit's world has moved by then.
    init(_ kind: ItemKind, target: SIMD3<Float>, scenes: [SyntheticScene], cameras: [CameraModel],
         drift: (Int) -> SIMD3<Float> = { _ in .zero }) {
        let anchor = scenes[0].tap(at: target, camera: cameras[0])!
        if kind == .light { measurements.setRule(.middle, for: id) }
        for (index, camera) in cameras.enumerated() {
            let scene = scenes[min(index, scenes.count - 1)]
            let depth = scene.render(from: camera, drift: drift(index), seed: UInt32(index))
            if let points = DepthGrouping.itemPoints(kind, anchor: anchor, depth: depth, camera: camera, floorY: 0) {
                measurements.addFrame(points, to: id, kind: kind, camera: camera)
            }
            outlines.append(outline)
        }
    }
}

/// Every side of `box` is within `margin` of the same side of `truth`.
private func matches(_ box: WorldBox?, _ truth: WorldBox, margin: Float = tolerance) -> Bool {
    guard let box else { return false }
    return all(abs(box.min - truth.min) .<= margin) && all(abs(box.max - truth.max) .<= margin)
}

@Suite("Scan scenes: the box hugs the tapped item")
struct ScanSceneTests {
    // A: a bottle 4 cm from a table's front edge, with the table's apron and legs under it.
    private let bottle = WorldBox(min: SIMD3(-0.04, 0.75, -1.72), max: SIMD3(0.04, 0.99, -1.64))
    private var table: [WorldBox] {
        [WorldBox(min: SIMD3(-0.6, 0.72, -2.4), max: SIMD3(0.6, 0.75, -1.6)),
         WorldBox(min: SIMD3(-0.6, 0.62, -1.62), max: SIMD3(0.6, 0.72, -1.6)),
         WorldBox(min: SIMD3(-0.6, 0, -1.64), max: SIMD3(-0.56, 0.72, -1.6)),
         WorldBox(min: SIMD3(0.56, 0, -1.64), max: SIMD3(0.6, 0.72, -1.6))]
    }

    @Test("A: a subject on a table gets a box around the bottle only, and its base is the bottle's")
    func subjectOnTable() throws {
        let target = SIMD3<Float>(0, 0.87, -1.68)
        let scene = SyntheticScene(boxes: [floorBox, bottle] + table)
        let scan = SceneScan(.subject, target: target, scenes: [scene],
                             cameras: SyntheticScene.walk(around: target, distance: 1.2, height: 1.3,
                                                          degrees: [-40, -30, -20, -10, 0, 10, 20, 30, 40]))

        // The lowest 2 cm sit in the gap kept above the tabletop (`DepthGrouping.supportGap`).
        let seen = WorldBox(min: SIMD3(bottle.min.x, bottle.min.y + DepthGrouping.supportGap, bottle.min.z),
                            max: bottle.max)
        #expect(matches(scan.outline, seen), "Outline: \(String(describing: scan.outline))")
        let base = try #require(scan.centres?.baseCentre)
        #expect(simd_distance(base, SIMD2(0, -1.68)) <= tolerance, "Base: \(base)")
        #expect(abs((scan.height ?? 0) - 0.99) <= tolerance, "Height: \(String(describing: scan.height))")
    }

    // B: a light head 3 cm in front of a backdrop, on a stand, with LiDAR's flying dots at its edges.
    private let head = WorldBox(min: SIMD3(-0.2, 1.4, -2.97), max: SIMD3(0.2, 1.7, -2.6))

    @Test("B: a light next to a backdrop gets a box around its head, not the backdrop or the stand")
    func lightByBackdrop() {
        let target = SIMD3<Float>(0, 1.55, -2.78)
        let scene = SyntheticScene(boxes: [floorBox, head,
                                           WorldBox(min: SIMD3(-1.5, 0, -3.03), max: SIMD3(1.5, 2.5, -3.0)),
                                           WorldBox(min: SIMD3(-0.015, 0, -2.8), max: SIMD3(0.015, 1.4, -2.77))],
                                   flyingPixels: true)
        let scan = SceneScan(.light, target: target, scenes: [scene],
                             cameras: SyntheticScene.walk(around: target, distance: 2.2, height: 1.5,
                                                          degrees: [-30, -20, -10, 0, 10, 20, 30]))

        #expect(matches(scan.outline, head), "Outline: \(String(describing: scan.outline))")
        #expect(abs((scan.height ?? 0) - 1.55) <= tolerance, "Height: \(String(describing: scan.height))")
    }

    @Test("C: a light 4 m away, seen at a steep angle, stays whole")
    func farSlantedLight() {
        let farHead = WorldBox(min: SIMD3(-0.2, 1.4, -0.2), max: SIMD3(0.2, 1.7, 0.2))
        let target = SIMD3<Float>(0, 1.55, 0)
        let scene = SyntheticScene(boxes: [floorBox, farHead,
                                           WorldBox(min: SIMD3(-0.015, 0, -0.015), max: SIMD3(0.015, 1.4, 0.015))])
        let scan = SceneScan(.light, target: target, scenes: [scene],
                             cameras: SyntheticScene.walk(around: target, distance: 4, height: 1.5,
                                                          degrees: [70, 72, 74, 76, 78, 80]))

        #expect(matches(scan.outline, farHead), "Outline: \(String(describing: scan.outline))")
        #expect(abs((scan.height ?? 0) - 1.55) <= tolerance, "Height: \(String(describing: scan.height))")
    }

    @Test("D: a camera on a tripod, with a person behind it, gets a box around the camera only")
    func cameraOnTripod() {
        let body = WorldBox(min: SIMD3(-0.07, 1.3, -0.06), max: SIMD3(0.07, 1.4, 0.06))
        let lens = WorldBox(min: SIMD3(-0.03, 1.32, 0.06), max: SIMD3(0.03, 1.38, 0.14))
        let target = SIMD3<Float>(0, 1.35, 0)
        let scene = SyntheticScene(boxes: [floorBox, body, lens,
                                           WorldBox(min: SIMD3(-0.03, 1.22, -0.03), max: SIMD3(0.03, 1.3, 0.03)),
                                           WorldBox(min: SIMD3(-0.015, 0, -0.015), max: SIMD3(0.015, 1.22, 0.015)),
                                           WorldBox(min: SIMD3(-0.2, 0, -0.45), max: SIMD3(0.2, 1.75, -0.25))])
        let scan = SceneScan(.camera, target: target, scenes: [scene],
                             cameras: SyntheticScene.walk(around: target, distance: 2, height: 1.4,
                                                          degrees: [-30, -20, -10, 0, 10, 20, 30]))

        let camera = WorldBox(min: body.min, max: SIMD3(body.max.x, body.max.y, lens.max.z))
        #expect(matches(scan.outline, camera), "Outline: \(String(describing: scan.outline))")
        #expect(abs((scan.height ?? 0) - 1.4) <= tolerance, "Height: \(String(describing: scan.height))")
    }

    @Test("E: frames where a person walks in front of the tapped light are skipped")
    func lightBehindPerson() {
        let lightHead = WorldBox(min: SIMD3(-0.2, 1.4, -0.2), max: SIMD3(0.2, 1.7, 0.2))
        let target = SIMD3<Float>(0, 1.55, 0.2)
        let room = [floorBox, lightHead, WorldBox(min: SIMD3(-0.015, 0, -0.015), max: SIMD3(0.015, 1.4, 0.015))]
        let person = WorldBox(min: SIMD3(-0.25, 0, 1.0), max: SIMD3(0.25, 1.8, 1.25))
        let clear = SyntheticScene(boxes: room), blocked = SyntheticScene(boxes: room + [person])
        let scan = SceneScan(.light, target: target, scenes: [clear, clear, clear, blocked, blocked, blocked],
                             cameras: SyntheticScene.walk(around: SIMD3(0, 1.55, 0), distance: 2.5, height: 1.5,
                                                          degrees: [0, 5, -5, 0, 5, -5]))

        // Only the head's front is ever in view here, so the box is that face; it never takes in the person.
        #expect(scan.outline.map { lightHead.grown(by: tolerance).holds($0) } == true,
                "Outline: \(String(describing: scan.outline))")
    }

    @Test("F: LiDAR's flying dots at the edges do not stretch the box")
    func strayDots() {
        let standing = WorldBox(min: SIMD3(-0.05, 0, -1.55), max: SIMD3(0.05, 0.3, -1.45))
        let target = SIMD3<Float>(0, 0.15, -1.5)
        let scene = SyntheticScene(boxes: [floorBox, standing,
                                           WorldBox(min: SIMD3(-2, 0, -2.53), max: SIMD3(2, 2.5, -2.5))],
                                   flyingPixels: true)
        let scan = SceneScan(.subject, target: target, scenes: [scene],
                             cameras: SyntheticScene.walk(around: target, distance: 1.2, height: 1.0,
                                                          degrees: [-30, -20, -10, 0, 10, 20, 30, 0, 10, -10]))

        // The lowest 3 cm are never painted: the floor's gap (`DepthGrouping.floorGap`).
        let seen = WorldBox(min: SIMD3(standing.min.x, DepthGrouping.floorGap, standing.min.z), max: standing.max)
        #expect(matches(scan.outline, seen), "Outline: \(String(describing: scan.outline))")
    }

    @Test("G: a mug by a desk's edge, scanned for 60 frames while ARKit drifts, keeps a box around the mug")
    func mugOverTime() {
        let mug = WorldBox(min: SIMD3(-0.045, 0.75, -1.70), max: SIMD3(0.045, 0.85, -1.62))
        let target = SIMD3<Float>(0, 0.8, -1.66)
        let scene = SyntheticScene(boxes: [floorBox, mug] + table, flyingPixels: true)
        let angles = (0..<60).map { Float(($0 % 12) - 6) * 4 }
        let drift = { (frame: Int) in SIMD3<Float>(0.01 * Float(frame / 10), 0, 0) }
        let scan = SceneScan(.subject, target: target, scenes: [scene],
                             cameras: SyntheticScene.walk(around: target, distance: 1.0, height: 1.2,
                                                          degrees: angles),
                             drift: drift)

        // The box may trail ARKit's drift over the recent frames (2 cm), never more, and never reaches the desk.
        let end = WorldBox(min: mug.min + drift(59), max: mug.max + drift(59))
        #expect(scan.outline.map { end.grown(by: 0.05).holds($0) } == true,
                "Outline: \(String(describing: scan.outline))")
        #expect(scan.outlines.dropFirst(5).allSatisfy { ($0?.min.y ?? 0) >= 0.72 },
                "The box reached below the desktop.")
    }

    @Test("H: a tap on a long bench spreads no further than the item's reach", arguments: [ItemKind.light, .camera])
    func stopsAtTheReach(kind: ItemKind) {
        // 5 m long and 50 cm tall: too low to count as a background wall, so only the reach stops the paint. From
        // 2.8 m the picture shows about 1.85 m of it each side of the tap.
        let bench = WorldBox(min: SIMD3(-2.5, 0, -3.2), max: SIMD3(2.5, 0.5, -2.8))
        let target = SIMD3<Float>(0, 0.25, -2.8)
        let scan = SceneScan(kind, target: target, scenes: [SyntheticScene(boxes: [floorBox, bench])],
                             cameras: [SyntheticScene.camera(at: SIMD3(0, 1, 0), lookingAt: target)])

        let reach = DepthGrouping.reach(kind)
        let outline = scan.outline
        #expect(outline.map { -reach - tolerance <= $0.min.x && $0.max.x <= reach + tolerance } == true,
                "Outline: \(String(describing: outline))")
        #expect(outline.map { $0.max.x >= reach - 0.1 } == true, "The paint stopped short of the reach.")
    }

    // I–K (Richie's office test, 27 Nov): a camera or a light can stand on a desk too, not only on a tripod or a stand.

    @Test("I and J: a camera or a light standing on a desk gets a box around the item, not the desk",
          arguments: [ItemKind.camera, .light])
    func itemOnDesk(kind: ItemKind) {
        let item = WorldBox(min: SIMD3(-0.08, 0.75, -1.84), max: SIMD3(0.08, 0.84, -1.74))
        let target = SIMD3<Float>(0, 0.8, -1.74)
        let scene = SyntheticScene(boxes: [floorBox, item] + table)
        let scan = SceneScan(kind, target: target, scenes: [scene],
                             cameras: SyntheticScene.walk(around: target, distance: 1.0, height: 1.35,
                                                          degrees: [-20, -10, 0, 10, 20]))

        // The lowest 2 cm sit in the gap kept above the desktop (`DepthGrouping.supportGap`).
        let seen = WorldBox(min: SIMD3(item.min.x, item.min.y + DepthGrouping.supportGap, item.min.z), max: item.max)
        #expect(matches(scan.outline, seen), "Outline: \(String(describing: scan.outline))")
    }

    @Test("K: a wide softbox close up keeps its whole head: its own front is not taken for a desk under it")
    func wideSoftbox() {
        let softbox = WorldBox(min: SIMD3(-0.3, 1.3, -0.3), max: SIMD3(0.3, 1.9, 0))
        let target = SIMD3<Float>(0, 1.6, 0)
        let scene = SyntheticScene(boxes: [floorBox, softbox,
                                           WorldBox(min: SIMD3(-0.015, 0, -0.165), max: SIMD3(0.015, 1.3, -0.135))])
        let scan = SceneScan(.light, target: target, scenes: [scene],
                             cameras: SyntheticScene.walk(around: target, distance: 1.5, height: 1.6,
                                                          degrees: [-10, -5, 0, 5, 10]))

        let outline = scan.outline
        #expect(outline.map { $0.min.y <= softbox.min.y + tolerance && $0.max.y >= softbox.max.y - tolerance } == true,
                "Outline: \(String(describing: outline))")
    }
}
