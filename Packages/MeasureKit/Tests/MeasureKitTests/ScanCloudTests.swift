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
    /// The lowest point of a wall 2 m away.
    private let wallBottom: Float = -0.7

    /// An item that was seen once: a wall at `depth` metres, read through `box`, with the given depth confidence.
    private func seen(atDepth depth: Float, box: NormalizedBox? = nil, confidence: UInt8 = 2) -> EquipmentPoints {
        var equipment = EquipmentPoints()
        let frame = makeFrame(depth: depth, confidence: confidence)
        equipment.add(box: box ?? wholeImage, mask: nil, depth: frame, camera: makeCamera())
        return equipment
    }

    @Test("Enough points near the floor are measured")
    func measured() {
        let item = seen(atDepth: 2).scanResult(floorY: wallBottom, isSubject: false)

        #expect(item.status == .measured)
        #expect(item.baseCentre != nil && item.topCentre != nil)
    }

    @Test("Too few points gives no centres")
    func tooFewPointsGivesNoCentres() {
        let item = seen(atDepth: 2, box: smallBox).scanResult(floorY: -1.2, isSubject: false)

        #expect(item.status == .tooFewPoints)
        #expect(item.baseCentre == nil && item.topCentre == nil)
    }

    @Test("An item 50 cm above the floor is measured from its top")
    func itemAboveTheFloor() throws {
        let item = seen(atDepth: 2).scanResult(floorY: -1.2, isSubject: false)

        #expect(item.status == .measured)
        let base = try #require(item.baseCentre)
        let top = try #require(item.topCentre)
        #expect(near(base, SIMD2(top.x, top.z)))
    }

    @Test("The subject may float above the floor")
    func subjectMayFloat() {
        let subject = seen(atDepth: 2).scanResult(floorY: -1.2, isSubject: true)

        #expect(subject.status == .measured)
    }

    @Test("Seen only beyond the range is out of range, not too few points")
    func outOfRange() {
        let item = seen(atDepth: 6).scanResult(floorY: wallBottom, isSubject: false)

        #expect(item.status == .outOfRange)
        #expect(item.baseCentre == nil && item.topCentre == nil)
    }

    @Test("No usable depth is not out of range")
    func noUsableDepthIsNotOutOfRange() {
        let item = seen(atDepth: 6, confidence: 0).scanResult(floorY: wallBottom, isSubject: false)

        #expect(item.status == .tooFewPoints)
    }

    @Test("Seen far first and near later is measured")
    func farThenNear() {
        var equipment = seen(atDepth: 6)
        equipment.add(box: wholeImage, mask: nil, depth: makeFrame(depth: 2), camera: makeCamera())

        let item = equipment.scanResult(floorY: wallBottom, isSubject: false)

        #expect(item.status == .measured)
    }
}

/// A10-41 part 2: the depth band is switched off for regions that are already bounded in 3D (the tapped spheres).
@Suite("Depth band (A10-41)")
struct DepthBandTests {
    @Test("The band keeps the nearest strip by default and both strips when switched off")
    func bandCanBeSwitchedOff() {
        // The left half of the frame is a strip 1 m away, the right half a strip 2 m away. The mask covers all of it.
        var depth = [Float](repeating: 2, count: 200)
        for row in 0..<10 { for column in 0..<10 { depth[row * 20 + column] = 1 } }
        let frame = DepthFrame(width: 20, height: 10, depth: depth, confidence: [UInt8](repeating: 2, count: 200))
        let mask = InstanceMask(width: 20, height: 10, pixels: [UInt8](repeating: 1, count: 200))
        let whole = NormalizedBox(x: 0, y: 0, width: 1, height: 1)

        var byDefault = EquipmentPoints()
        byDefault.add(box: whole, mask: mask, depth: frame, camera: makeCamera())
        var bandOff = EquipmentPoints()
        bandOff.add(box: whole, mask: mask, depth: frame, camera: makeCamera(), depthBand: .infinity)

        #expect(!byDefault.points.isEmpty)
        #expect(byDefault.points.allSatisfy { near($0.z, -1) })
        #expect(bandOff.points.contains { near($0.z, -2) })
        #expect(bandOff.points.count > byDefault.points.count)
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

    @Test("The centres are available, for drawing markers")
    func centresForMarkers() throws {
        var scan = ScanMeasurements()
        see(item, wallAt: 2, from: camera(movedAlongX: 1), in: &scan)

        let centres = try #require(scan.centres(subject: subject, floorY: floorY)[item])
        let base = try #require(centres.baseCentre)
        let top = try #require(centres.topCentre)

        // The wall is centred on x = 1 here, 2 m away (z = -2), and 0.7 m above the camera at its top.
        #expect(centres.status == .measured)
        #expect(near(base, SIMD2(1, -2), 0.001))
        #expect(near(top, SIMD3(1, 0.7, -2), 0.001))
    }

    /// `subject` is the wall seen from the origin, centred on x = 0, y = 0, z = -2; `item` is the same wall seen from a
    /// camera `metres` further along x, so it is centred on x = `metres`.
    private func twoItems(metresApart metres: Float) -> ScanMeasurements {
        var scan = ScanMeasurements()
        see(subject, wallAt: 2, in: &scan)
        see(item, wallAt: 2, from: camera(movedAlongX: metres), in: &scan)
        return scan
    }

    @Test("The nearest item within range is found")
    func nearestItemWithinRange() {
        let scan = twoItems(metresApart: 2)

        #expect(scan.nearestItem(to: SIMD3(0.1, 0, -2), maxDistance: 0.4, among: [subject, item]) == subject)
        #expect(scan.nearestItem(to: SIMD3(1.9, 0, -2), maxDistance: 0.4, among: [subject, item]) == item)
    }

    @Test("Of two items in range, the nearer wins, whatever the order")
    func nearerOfTwoWins() {
        let scan = twoItems(metresApart: 0.5)

        #expect(scan.nearestItem(to: SIMD3(0.2, 0, -2), maxDistance: 1, among: [subject, item]) == subject)
        #expect(scan.nearestItem(to: SIMD3(0.2, 0, -2), maxDistance: 1, among: [item, subject]) == subject)
        #expect(scan.nearestItem(to: SIMD3(0.4, 0, -2), maxDistance: 1, among: [subject, item]) == item)
        #expect(scan.nearestItem(to: SIMD3(0.4, 0, -2), maxDistance: 1, among: [item, subject]) == item)
    }

    @Test("No item is returned when nothing qualifies")
    func noItemWhenNothingQualifies() {
        let scan = twoItems(metresApart: 2)

        // Nothing within 0.4 m of a point between the two items.
        #expect(scan.nearestItem(to: SIMD3(1, 0, -2), maxDistance: 0.4, among: [subject, item]) == nil)
        // Only the listed candidates count: the first item is near the point but not listed.
        #expect(scan.nearestItem(to: SIMD3(0.1, 0, -2), maxDistance: 0.4, among: [item]) == nil)
        // An id that was never added, and no candidates at all.
        #expect(scan.nearestItem(to: SIMD3(0, 0, -2), maxDistance: 10, among: [UUID()]) == nil)
        #expect(scan.nearestItem(to: SIMD3(0, 0, -2), maxDistance: 10, among: []) == nil)
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
