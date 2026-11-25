import Foundation
import Testing
import simd
@testable import MeasureKit

/// A10-41 per-item point cases. Walls at one depth make every depth pixel the same distance from the iPhone.
@Suite("Equipment points (A10-41)")
struct EquipmentPointsTests {
    /// A camera `metres` further back (+z) than the origin: the same wall then lands at a different world z.
    private func cameraMovedBack(_ metres: Float) -> CameraModel {
        var pose = matrix_identity_float4x4
        pose.columns.3 = SIMD4(0, 0, metres, 1)
        return makeCamera(pose: pose)
    }

    @Test("Points from two frames taken at different places are all kept")
    func twoFramesMerge() {
        var equipment = EquipmentPoints()
        equipment.add(points: wallPoints(depth: 2), camera: makeCamera())
        let afterOneFrame = equipment.points.count
        equipment.add(points: wallPoints(depth: 2, camera: cameraMovedBack(1)), camera: cameraMovedBack(1))

        #expect(afterOneFrame > 0)
        #expect(equipment.points.count == 2 * afterOneFrame)
    }

    @Test("The same spot seen again is counted once")
    func sameSpotCountedOnce() {
        var equipment = EquipmentPoints()
        equipment.add(points: wallPoints(depth: 2), camera: makeCamera())
        let afterOneFrame = equipment.points.count
        equipment.add(points: wallPoints(depth: 2), camera: makeCamera())

        #expect(afterOneFrame > 0)
        #expect(equipment.points.count == afterOneFrame)
    }

    @Test("Beyond range in every frame gives no points and is remembered")
    func beyondRangeIsRemembered() {
        var equipment = EquipmentPoints()
        equipment.add(points: wallPoints(depth: 6), camera: makeCamera())

        #expect(equipment.points.isEmpty)
        #expect(equipment.sawPointsBeyondRange)
    }

    @Test("Within range gives points and no beyond-range mark")
    func withinRange() {
        var equipment = EquipmentPoints()
        equipment.add(points: wallPoints(depth: 2), camera: makeCamera())

        #expect(!equipment.points.isEmpty)
        #expect(!equipment.sawPointsBeyondRange)
    }
}

/// A10-20 test cases. A flat wall in front of the iPhone makes the points: a wall 2 m away gives 128 points
/// from y = +0.7 down to y = -0.7, so its lowest point is at -0.7.
@Suite("Equipment status (A10-20)")
struct EquipmentStatusTests {
    /// An item that was seen once: a wall at `depth` metres, only its first `count` points when given.
    private func seen(atDepth depth: Float, count: Int? = nil) -> EquipmentPoints {
        var equipment = EquipmentPoints()
        let wall = wallPoints(depth: depth)
        equipment.add(points: Array(wall.prefix(count ?? wall.count)), camera: makeCamera())
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
        let item = seen(atDepth: 2, count: 8).scanResult(isSubject: false)

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
        let item = seen(atDepth: 6, count: 0).scanResult(isSubject: false)

        #expect(item.status == .tooFewPoints)
    }

    @Test("Seen far first and near later is measured")
    func farThenNear() {
        var equipment = seen(atDepth: 6)
        equipment.add(points: wallPoints(depth: 2), camera: makeCamera())

        let item = equipment.scanResult(isSubject: false)

        #expect(item.status == .measured)
    }
}

/// A10-41 part 2: results for a whole scan. A wall 2 m away gives 128 points, 1.4 m tall, with the floor at y = -0.7.
@Suite("Scan measurements (A10-41)")
struct ScanMeasurementsTests {
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
        scan.add(points: wallPoints(depth: depth, camera: camera), to: id, camera: camera)
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

/// Equipment points handed over directly (a painted column).
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

/// The centre rule per item: lights are measured at the middle of the head, everything else as before.
@Suite("Centre rule per item")
struct CentreRulePerItemTests {
    private let subject = UUID()
    private let light = UUID()
    private let camera = UUID()

    private func scan() -> ScanMeasurements {
        var scan = ScanMeasurements()
        let cam = makeCamera()
        let wall = SyntheticEquipment.column(x: 0, z: -300, bottom: 0, top: 120, total: 120)
        scan.add(points: SyntheticEquipment.column(x: 100, z: -300, bottom: 0, top: 100, total: 120),
                 to: subject, camera: cam)
        scan.add(points: wall, to: light, camera: cam)
        scan.add(points: wall, to: camera, camera: cam)
        return scan
    }

    @Test("An item with the middle rule is measured at the middle, one without it at its top")
    func middleAndTop() throws {
        var scan = scan()
        scan.setRule(.middle, for: light)

        let results = scan.results(subject: subject, floorY: 0)

        #expect(near(try #require(results[light]?.height), 0.6, 0.02))
        #expect(near(try #require(results[camera]?.height), 1.2, 0.03))
    }

    @Test("Removing an item forgets its rule")
    func removeForgetsTheRule() throws {
        var scan = scan()
        scan.setRule(.middle, for: light)
        scan.remove(light)

        scan.add(points: SyntheticEquipment.column(x: 0, z: -300, bottom: 0, top: 120, total: 120),
                 to: light, camera: makeCamera())

        #expect(near(try #require(scan.results(subject: subject, floorY: 0)[light]?.height), 1.2, 0.03))
    }
}

/// O8 (A10-121): an item's centres are worked out again only after the item changed.
@Suite("Centres cache")
struct CentresCacheTests {
    private let floorY: Float = -0.7
    private let subject = UUID()
    private let item = UUID()

    /// A camera `metres` further along x: the same wall then lands `metres` to the right in the world.
    private func camera(movedAlongX metres: Float) -> CameraModel {
        var pose = matrix_identity_float4x4
        pose.columns.3 = SIMD4(metres, 0, 0, 1)
        return makeCamera(pose: pose)
    }

    /// A scan with a subject and an item, both seeing a wall 2 m away.
    private func twoItemScan() -> ScanMeasurements {
        var scan = ScanMeasurements()
        scan.add(points: wallPoints(depth: 2), to: subject, camera: makeCamera())
        scan.add(points: wallPoints(depth: 2), to: item, camera: makeCamera())
        return scan
    }

    @Test("C1: a point in a known cell is not new")
    func aPointInAKnownCellIsNotNew() {
        var scan = ScanMeasurements()
        let points = (0..<10).map { SIMD3<Float>(Float($0) * 0.1, 0.5, -2) }

        let first = scan.add(points: points, to: item, camera: makeCamera())
        let second = scan.add(points: points, to: item, camera: makeCamera())

        #expect(first == 10)
        #expect(second == 0)
    }

    @Test("C2: results without new points are not calculated again")
    func resultsWithoutNewPointsAreNotCalculatedAgain() {
        var scan = twoItemScan()

        let first = scan.cachedResults(subject: subject, floorY: floorY)
        let callsAfterFirst = scan.centresCalculations
        let second = scan.cachedResults(subject: subject, floorY: floorY)

        #expect(callsAfterFirst == 2)
        #expect(scan.centresCalculations == 2)
        #expect(first == second)
    }

    @Test("C3: only the changed item is calculated again")
    func onlyTheChangedItemIsCalculatedAgain() {
        var scan = twoItemScan()
        _ = scan.cachedResults(subject: subject, floorY: floorY)
        let callsAfterFirst = scan.centresCalculations

        let moved = camera(movedAlongX: 1)
        let added = scan.add(points: wallPoints(depth: 2, camera: moved), to: item, camera: moved)
        let results = scan.cachedResults(subject: subject, floorY: floorY)

        #expect(added > 0)
        #expect(scan.centresCalculations == callsAfterFirst + 1)
        #expect(results == scan.results(subject: subject, floorY: floorY))
    }

    /// What happens to an item between two calls of `cachedResults`.
    enum Change: CaseIterable, Sendable {
        case ruleChanged, removedAndAddedAgain, surfaceAdded, farPointsOnly
    }

    @Test("C4: a change makes the item calculate again", arguments: Change.allCases)
    func aChangeMakesTheItemCalculateAgain(change: Change) throws {
        var scan = twoItemScan()
        // An item that has no point yet: its entry exists, so the far case can change it.
        let farItem = UUID()
        scan.add(points: [], to: farItem, camera: makeCamera())
        let before = scan.cachedResults(subject: subject, floorY: floorY)
        let callsBefore = scan.centresCalculations
        #expect(callsBefore == 3)
        #expect(try #require(before[farItem]).status == .tooFewPoints)

        switch change {
        case .ruleChanged:
            scan.setRule(.middle, for: item)
        case .removedAndAddedAgain:
            // An empty add makes no change by itself, so only remove can empty the cache here (as a re-tapped
            // subject: remove, then a column with no points yet).
            scan.remove(item)
            scan.add(points: [], to: item, camera: makeCamera())
        case .surfaceAdded:
            // The same points again: none is new, but 20 or more of them make a small box.
            scan.addSurface(points: wallPoints(depth: 2), to: item, camera: makeCamera())
        case .farPointsOnly:
            scan.add(points: wallPoints(depth: 6), to: farItem, camera: makeCamera())
        }
        let after = scan.cachedResults(subject: subject, floorY: floorY)

        #expect(scan.centresCalculations == callsBefore + 1)
        #expect(after == scan.results(subject: subject, floorY: floorY))
        if change == .surfaceAdded {
            #expect(after[item]?.pointCount == before[item]?.pointCount)
        }
        if change == .farPointsOnly {
            #expect(try #require(after[farItem]).status == .outOfRange)
        }
        if change == .removedAndAddedAgain {
            #expect(try #require(after[item]).status == .tooFewPoints)
        }
    }

    @Test("C5: cached results match results")
    func cachedResultsMatchResults() {
        var scan = twoItemScan()
        let moved = camera(movedAlongX: 1)
        scan.add(points: wallPoints(depth: 2, camera: moved), to: item, camera: moved)

        let cached = scan.cachedResults(subject: subject, floorY: floorY)

        #expect(cached == scan.results(subject: subject, floorY: floorY))
        // The two views of the wall overlap, so there are more than 128 points but fewer than 256.
        #expect((cached[item]?.pointCount ?? 0) > 128)
    }
}
