import Foundation
import Testing
import simd
@testable import MeasureKit

@Suite struct ScanCloudTests {
    private func pt(_ x: Float, _ y: Float = 0, _ z: Float = 0, _ c: UInt8 = 0) -> (world: SIMD3<Float>, rgb: SIMD3<UInt8>) {
        (SIMD3(x, y, z), SIMD3(c, c, c))
    }

    @Test func firstPointInAVoxelWins() {
        var cloud = ScanCloud()
        let added = cloud.add([pt(0.101, 0, 0, 1), pt(0.105, 0, 0, 2)])   // same 1 cm voxel
        #expect(added.count == 1 && added[0].rgb == SIMD3(1, 1, 1))
        #expect(cloud.count == 1)
    }

    @Test func differentVoxelsBothAdded() {
        var cloud = ScanCloud()
        #expect(cloud.add([pt(0.101), pt(0.112)]).count == 2)
        #expect(cloud.count == 2 && cloud.allPoints.count == 2)
    }

    @Test func addReturnsOnlyNewPoints() {
        var cloud = ScanCloud()
        _ = cloud.add([pt(0.101)])
        let added = cloud.add([pt(0.103, 0, 0, 9), pt(0.5, 0, 0, 7)])
        #expect(added.count == 1 && added[0].rgb == SIMD3(7, 7, 7))
        #expect(cloud.count == 2)
    }

    @Test func negativeCoordinatesUseFloorVoxels() {
        var cloud = ScanCloud()
        // -0.004 and +0.004 straddle zero: different voxels.
        #expect(cloud.add([pt(-0.004), pt(0.004)]).count == 2)
    }

    @Test func stopsAtMaxPoints() {
        var cloud = ScanCloud(maxPoints: 3)
        let added = cloud.add((0..<5).map { pt(Float($0) * 0.05) })
        #expect(added.count == 3 && cloud.count == 3)
        #expect(cloud.add([pt(9)]).isEmpty)
        #expect(ScanCloud.maxPoints == 600_000 && ScanCloud.voxelSize == 0.01)
    }

    @Test func removeAllEmptiesAndFreesVoxels() {
        var cloud = ScanCloud()
        _ = cloud.add([pt(0.101)])
        cloud.removeAll()
        #expect(cloud.count == 0 && cloud.allPoints.isEmpty)
        #expect(cloud.add([pt(0.101)]).count == 1)
    }
}

/// A10-41 per-item point cases. Walls at one depth make every depth pixel the same distance from the iPhone.
@Suite("Equipment points (A10-41)")
struct EquipmentPointsTests {
    private let wholeImage = NormalizedBox(x: 0, y: 0, width: 1, height: 1)

    /// A camera `metres` further back (+z) than the origin: the same wall then lands at a different world z.
    private func cameraMovedBack(_ metres: Float) -> CameraModel {
        var pose = matrix_identity_float4x4
        pose.columns.3 = SIMD4(0, 0, metres, 1)
        return makeCamera(pose: pose)
    }

    @Test("Points from two frames taken at different places are all kept")
    func twoFramesMerge() {
        var equipment = EquipmentPoints()
        equipment.add(box: wholeImage, mask: nil, depth: makeFrame(depth: 2), camera: makeCamera())
        let afterOneFrame = equipment.points.count
        equipment.add(box: wholeImage, mask: nil, depth: makeFrame(depth: 2), camera: cameraMovedBack(1))

        #expect(afterOneFrame > 0)
        #expect(equipment.points.count == 2 * afterOneFrame)
    }

    @Test("The same spot seen again is counted once")
    func sameSpotCountedOnce() {
        var equipment = EquipmentPoints()
        equipment.add(box: wholeImage, mask: nil, depth: makeFrame(depth: 2), camera: makeCamera())
        let afterOneFrame = equipment.points.count
        equipment.add(box: wholeImage, mask: nil, depth: makeFrame(depth: 2), camera: makeCamera())

        #expect(afterOneFrame > 0)
        #expect(equipment.points.count == afterOneFrame)
    }

    @Test("Beyond range in every frame gives no points and is remembered")
    func beyondRangeIsRemembered() {
        var equipment = EquipmentPoints()
        equipment.add(box: wholeImage, mask: nil, depth: makeFrame(depth: 6), camera: makeCamera())

        #expect(equipment.points.isEmpty)
        #expect(equipment.sawPointsBeyondRange)
    }

    @Test("Within range gives points and no beyond-range mark")
    func withinRange() {
        var equipment = EquipmentPoints()
        equipment.add(box: wholeImage, mask: nil, depth: makeFrame(depth: 2), camera: makeCamera())

        #expect(!equipment.points.isEmpty)
        #expect(!equipment.sawPointsBeyondRange)
    }

    @Test("Nothing usable seen is not the same as out of range")
    func nothingUsableSeen() {
        var lowConfidence = EquipmentPoints()
        lowConfidence.add(box: wholeImage, mask: nil, depth: makeFrame(depth: 6, confidence: 0), camera: makeCamera())
        var noArea = EquipmentPoints()
        noArea.add(box: NormalizedBox(x: 0.5, y: 0.5, width: 0, height: 0), mask: nil,
                   depth: makeFrame(depth: 6), camera: makeCamera())

        #expect(lowConfidence.points.isEmpty && !lowConfidence.sawPointsBeyondRange)
        #expect(noArea.points.isEmpty && !noArea.sawPointsBeyondRange)
    }

    @Test("A mask is used instead of the box")
    func maskIsPreferred() {
        var pixels = [UInt8](repeating: 0, count: 200)
        for row in 2...7 { for column in 5...14 { pixels[row * 20 + column] = 1 } }
        let mask = InstanceMask(width: 20, height: 10, pixels: pixels)
        let frame = makeFrame(depth: 2)
        let maskOnly = DepthSampler.worldPoints(in: mask, depth: frame, camera: makeCamera())
        let boxOnly = DepthSampler.worldPoints(in: wholeImage, depth: frame, camera: makeCamera())

        var equipment = EquipmentPoints()
        equipment.add(box: wholeImage, mask: mask, depth: frame, camera: makeCamera())

        #expect(maskOnly.count < boxOnly.count)
        #expect(equipment.points.count == maskOnly.count)
    }
}

/// A10-20 test cases. A flat wall in front of the iPhone makes the points: a wall 2 m away gives 128 points
/// from y = +0.7 down to y = -0.7, so its lowest point is at -0.7.
@Suite("Equipment status (A10-20)")
struct EquipmentStatusTests {
    private let wholeImage = NormalizedBox(x: 0, y: 0, width: 1, height: 1)
    /// A small box that catches only 8 depth pixels of the wall.
    private let smallBox = NormalizedBox(x: 0.4, y: 0.4, width: 0.2, height: 0.2)

    /// An item that was seen once: a wall at `depth` metres, read through `box`, with the given depth confidence.
    private func seen(atDepth depth: Float, box: NormalizedBox? = nil, confidence: UInt8 = 2) -> EquipmentPoints {
        var equipment = EquipmentPoints()
        let frame = makeFrame(depth: depth, confidence: confidence)
        equipment.add(box: box ?? wholeImage, mask: nil, depth: frame, camera: makeCamera())
        return equipment
    }

    @Test("Enough points are measured")
    func measured() {
        let item = seen(atDepth: 2).scanResult(isSubject: false)

        #expect(item.status == .measured)
        #expect(item.baseCentre != nil && item.topCentre != nil)
    }

    @Test("Too few points gives no centres")
    func tooFewPointsGivesNoCentres() {
        let item = seen(atDepth: 2, box: smallBox).scanResult(isSubject: false)

        #expect(item.status == .tooFewPoints)
        #expect(item.baseCentre == nil && item.topCentre == nil)
    }

    @Test("An item is measured from its top, with its base under it")
    func itemMeasuredFromItsTop() throws {
        let item = seen(atDepth: 2).scanResult(isSubject: false)

        #expect(item.status == .measured)
        let base = try #require(item.baseCentre)
        let top = try #require(item.topCentre)
        #expect(near(base, SIMD2(top.x, top.z)))
    }

    @Test("Seen only beyond the range is out of range, not too few points")
    func outOfRange() {
        let item = seen(atDepth: 6).scanResult(isSubject: false)

        #expect(item.status == .outOfRange)
        #expect(item.baseCentre == nil && item.topCentre == nil)
    }

    @Test("No usable depth is not out of range")
    func noUsableDepthIsNotOutOfRange() {
        let item = seen(atDepth: 6, confidence: 0).scanResult(isSubject: false)

        #expect(item.status == .tooFewPoints)
    }

    @Test("Seen far first and near later is measured")
    func farThenNear() {
        var equipment = seen(atDepth: 6)
        equipment.add(box: wholeImage, mask: nil, depth: makeFrame(depth: 2), camera: makeCamera())

        let item = equipment.scanResult(isSubject: false)

        #expect(item.status == .measured)
    }
}

/// A10-41 part 2: results for a whole scan. A wall 2 m away gives 128 points, 1.4 m tall, with the floor at y = -0.7.
@Suite("Scan measurements (A10-41)")
struct ScanMeasurementsTests {
    private let wholeImage = NormalizedBox(x: 0, y: 0, width: 1, height: 1)
    private let floorY: Float = -0.7
    private let subject = UUID()
    private let item = UUID()

    /// A camera `metres` further along x: the same wall then lands `metres` to the right in the world.
    private func camera(movedAlongX metres: Float) -> CameraModel {
        var pose = matrix_identity_float4x4
        pose.columns.3 = SIMD4(metres, 0, 0, 1)
        return makeCamera(pose: pose)
    }

    private func see(
        _ id: UUID, wallAt depth: Float, from camera: CameraModel = makeCamera(), in scan: inout ScanMeasurements
    ) {
        scan.add(to: id, box: wholeImage, mask: nil, depth: makeFrame(depth: depth), camera: camera)
    }

    @Test("A subject and an item, both measured, give distance, floor position and height")
    func bothMeasured() throws {
        var scan = ScanMeasurements()
        see(subject, wallAt: 2, in: &scan)
        see(item, wallAt: 2, from: camera(movedAlongX: 1), in: &scan)

        let result = try #require(scan.results(subject: subject, floorY: floorY)[item])
        let distance = try #require(result.distanceToSubject)
        let offset = try #require(result.floorOffset)
        let height = try #require(result.height)

        #expect(result.status == .measured)
        #expect(near(distance, 1, 0.001))
        #expect(near(offset, SIMD2(1, 0), 0.001))
        #expect(near(height, 1.4, 0.001))
    }

    @Test("An out-of-range subject blocks distances but not heights")
    func outOfRangeSubject() throws {
        var scan = ScanMeasurements()
        see(subject, wallAt: 6, in: &scan)
        see(item, wallAt: 2, in: &scan)

        let results = scan.results(subject: subject, floorY: floorY)
        let result = try #require(results[item])
        let height = try #require(result.height)

        #expect(try #require(results[subject]).status == .outOfRange)
        #expect(result.distanceToSubject == nil)
        #expect(result.floorOffset == nil)
        #expect(near(height, 1.4, 0.001))
    }

    @Test("An out-of-range item has no values, and the subject is unaffected")
    func outOfRangeItem() throws {
        var scan = ScanMeasurements()
        see(subject, wallAt: 2, in: &scan)
        see(item, wallAt: 6, in: &scan)

        let results = scan.results(subject: subject, floorY: floorY)
        let result = try #require(results[item])
        let subjectResult = try #require(results[subject])

        #expect(result.status == .outOfRange)
        #expect(result.distanceToSubject == nil && result.height == nil && result.floorOffset == nil)
        #expect(subjectResult.status == .measured)
        #expect(subjectResult.height != nil)
    }

    @Test("Without a subject there are no distances, and heights follow each item")
    func noSubject() throws {
        var scan = ScanMeasurements()
        see(item, wallAt: 2, in: &scan)

        let result = try #require(scan.results(subject: UUID(), floorY: floorY)[item])
        let height = try #require(result.height)

        #expect(result.status == .measured)
        #expect(result.distanceToSubject == nil)
        #expect(result.floorOffset == nil)
        #expect(near(height, 1.4, 0.001))
    }

    @Test("The result says how many points the item has")
    func pointCount() throws {
        var scan = ScanMeasurements()
        see(item, wallAt: 2, in: &scan)

        let result = try #require(scan.results(subject: subject, floorY: floorY)[item])

        #expect(result.pointCount == 128)
    }

    @Test("A subject and an item above the floor are both measured")
    func floatingSubjectAndItem() throws {
        var scan = ScanMeasurements()
        see(subject, wallAt: 2, in: &scan)
        see(item, wallAt: 2, in: &scan)

        // The floor is 50 cm below the lowest point of both walls: a product on a table and a light head are fine.
        let results = scan.results(subject: subject, floorY: -1.2)

        #expect(try #require(results[subject]).status == .measured)
        #expect(try #require(results[item]).status == .measured)
    }

    @Test("Removing an item forgets its points and keeps the others")
    func removeForgetsOneItem() throws {
        var scan = ScanMeasurements()
        see(subject, wallAt: 2, in: &scan)
        see(item, wallAt: 2, in: &scan)

        scan.remove(item)
        scan.remove(UUID())

        let results = scan.results(subject: subject, floorY: floorY)
        let subjectResult = try #require(results[subject])
        #expect(results[item] == nil)
        #expect(subjectResult.pointCount == 128)
    }
}

/// Equipment points handed over directly (a painted column), with the same rules as points from a mask.
@Suite("Adding points directly")
struct AddPointsTests {
    @Test("Points in the same 1 cm cell are kept once")
    func sameCellOnce() {
        var points = EquipmentPoints()

        points.add(points: [SIMD3(0.101, 0.5, -2), SIMD3(0.105, 0.5, -2), SIMD3(0.2, 0.5, -2)], camera: makeCamera())
        points.add(points: [SIMD3(0.102, 0.5, -2)], camera: makeCamera())

        #expect(points.points.count == 2)
    }

    @Test("Points beyond the range are dropped, and only far points mean out of range")
    func beyondRange() {
        var far = EquipmentPoints()
        far.add(points: [SIMD3(0, 0.5, -6), SIMD3(0.5, 0.5, -7)], camera: makeCamera())
        #expect(far.points.isEmpty)
        #expect(far.scanResult(isSubject: false).status == .outOfRange)

        var mixed = EquipmentPoints()
        mixed.add(points: [SIMD3(0, 0.5, -6), SIMD3(0, 0.5, -2)], camera: makeCamera())
        #expect(mixed.points.count == 1)
        #expect(mixed.scanResult(isSubject: false).status == .tooFewPoints)
    }

    @Test("No points at all is not out of range")
    func noPoints() {
        var points = EquipmentPoints()
        points.add(points: [], camera: makeCamera())
        #expect(points.scanResult(isSubject: false).status == .tooFewPoints)
    }

    @Test("A scan result from added points gives the item's measurements")
    func resultFromPoints() throws {
        let subject = UUID(), light = UUID()
        var scan = ScanMeasurements()
        let camera = makeCamera()
        scan.add(points: SyntheticEquipment.column(x: 0, z: -300, bottom: 0, top: 100, total: 120),
                 to: subject, camera: camera)
        // The 98th percentile of evenly spread points lies a little under the top, by design.
        scan.add(points: SyntheticEquipment.column(x: 100, z: -300, bottom: 0, top: 120, total: 120),
                 to: light, camera: camera)

        let result = try #require(scan.results(subject: subject, floorY: 0)[light])

        #expect(result.status == .measured)
        #expect(near(try #require(result.distanceToSubject), 1, 0.001))
        #expect(near(try #require(result.height), 1.2, 0.03))
    }
}
