import Testing
import simd
@testable import MeasureKit

@Suite struct GeometryTests {
    @Test func medianIgnoresOneFarOutlier() {
        let pts: [SIMD3<Float>] = [SIMD3(1, 1, 1), SIMD3(1.1, 1.1, 1.1), SIMD3(0.9, 0.9, 0.9),
                                   SIMD3(1.05, 1.05, 1.05), SIMD3(100, 100, 100)]
        let m = Geometry.medianPoint(pts)!
        #expect(near(m, SIMD3(1.05, 1.05, 1.05)))
        #expect(Geometry.medianPoint([]) == nil)
    }

    @Test func principalAxisOfVerticalLine() {
        let pts = (0..<10).map { SIMD3<Float>(0.3, Float($0) * 0.1, -1) }
        let axis = Geometry.principalAxis(pts)!
        #expect(near(axis, SIMD3(0, 1, 0)))
    }

    @Test func principalAxisOf45DegreeLineGivesTilt45() {
        let pts = (0..<10).map { SIMD3<Float>(Float($0) * 0.1, Float($0) * 0.1, -1) }
        let axis = Geometry.principalAxis(pts)!
        #expect(axis.y >= 0)
        #expect(abs(Geometry.tiltDegrees(axis: axis) - 45) < 0.5)
    }

    @Test func principalAxisNilForTooFewPoints() {
        #expect(Geometry.principalAxis([]) == nil)
        #expect(Geometry.principalAxis([SIMD3(0, 0, 0), SIMD3(0, 1, 0)]) == nil)
    }

    @Test func principalAxisNilWithoutDominantDirection() {
        // A flat square grid: both in-plane eigenvalues are equal.
        var pts: [SIMD3<Float>] = []
        for i in 0..<5 { for j in 0..<5 { pts.append(SIMD3(Float(i), Float(j), 0)) } }
        #expect(Geometry.principalAxis(pts) == nil)
    }

    @Test func tiltDegrees() {
        #expect(abs(Geometry.tiltDegrees(axis: SIMD3(0, 1, 0))) < 0.5)
        #expect(abs(Geometry.tiltDegrees(axis: SIMD3(1, 0, 0)) - 90) < 0.5)
        #expect(abs(Geometry.tiltDegrees(axis: SIMD3(0, -1, 0))) < 0.5)
        let a = Geometry.tiltDegrees(axis: SIMD3(1, 1, 0))
        let b = Geometry.tiltDegrees(axis: SIMD3(-1, -1, 0))
        #expect(abs(a - b) < 1e-4)
    }

    @Test func aimOffsetDegrees() {
        let from = SIMD3<Float>(0, 0, 0)
        let toX = SIMD3<Float>(5, 0, 0)
        let toZ = SIMD3<Float>(0, 0, 5)
        #expect(abs(Geometry.aimOffsetDegrees(axis: SIMD3(1, 0, 0), from: from, to: toX)! - 0) < 0.5)
        #expect(abs(Geometry.aimOffsetDegrees(axis: SIMD3(1, 0, 0), from: from, to: toZ)! - 90) < 0.5)
        #expect(abs(Geometry.aimOffsetDegrees(axis: SIMD3(-1, 0, 0), from: from, to: toX)! - 0) < 0.5)
        #expect(abs(Geometry.aimOffsetDegrees(axis: SIMD3(1, 0, 1), from: from, to: toX)! - 45) < 0.5)
        #expect(Geometry.aimOffsetDegrees(axis: SIMD3(0, 1, 0), from: from, to: toX) == nil)
        // About 10° from vertical: below minAimTiltDegrees, so no aim.
        #expect(Geometry.aimOffsetDegrees(axis: simd_normalize(SIMD3(0.17, 1, 0)), from: from, to: toX) == nil)
        // Target straight above the object has no horizontal direction.
        #expect(Geometry.aimOffsetDegrees(axis: SIMD3(1, 0, 0), from: from, to: SIMD3(0, 3, 0)) == nil)
    }

    @Test func aimNeedsAtLeastMinAimTilt() {
        // Review finding 4: at small tilts the horizontal direction is LiDAR noise, so no aim.
        func axis(tilt degrees: Float) -> SIMD3<Float> {
            let r = degrees * .pi / 180
            return SIMD3(sin(r), cos(r), 0)
        }
        let from = SIMD3<Float>(0, 0, 0), to = SIMD3<Float>(5, 0, 0)
        #expect(Geometry.aimOffsetDegrees(axis: axis(tilt: 15), from: from, to: to) == nil)
        #expect(Geometry.aimOffsetDegrees(axis: axis(tilt: Geometry.minAimTiltDegrees - 0.5), from: from, to: to) == nil)
        #expect(Geometry.aimOffsetDegrees(axis: axis(tilt: Geometry.minAimTiltDegrees + 0.5), from: from, to: to) != nil)
    }

    @Test func heightAboveFloor() {
        #expect(near(Geometry.heightAboveFloor(SIMD3(1, 0.8, 2), floorY: -0.2), 1.0))
    }
}

/// A10-42 test cases. Lengths in the written cases are whole centimetres; `cm(_:)` converts them to metres.
@Suite("Equipment centres (A10-42)")
struct EquipmentCentresTests {
    /// A piece of equipment standing at x = 200 cm, z = 300 cm.
    private func equipment(bottom: Float, top: Float, total: Int = 100) -> [SIMD3<Float>] {
        SyntheticEquipment.column(x: 200, z: 300, bottom: bottom, top: top, total: total)
    }

    // MARK: Happy paths

    @Test("A vertical item gets its base centre and top centre")
    func verticalItem() throws {
        let result = Geometry.centres(of: equipment(bottom: 0, top: 180), floorY: 0, isSubject: false)

        #expect(result.status == .measured)
        let base = try #require(result.baseCentre)
        let top = try #require(result.topCentre)
        #expect(near(base, SIMD2(cm(200), cm(300)), cm(1)))
        #expect(near(top, SIMD3(cm(200), cm(180), cm(300)), cm(1)))
    }

    @Test("The base centre of a tripod lands between the legs")
    func tripodWithSpreadLegs() throws {
        let legs = SyntheticEquipment.tripodLegs(x: 200, z: 300, radius: 40, height: 10, pointsPerLeg: 10)
        let column = SyntheticEquipment.column(x: 200, z: 300, bottom: 20, top: 180, total: 80)

        let result = Geometry.centres(of: legs + column, floorY: 0, isSubject: false)

        #expect(result.status == .measured)
        let base = try #require(result.baseCentre)
        #expect(near(base, SIMD2(cm(200), cm(300)), cm(2)))
    }

    @Test("The top includes the modifier, the base stays at the stand")
    func topIncludesModifier() throws {
        let stand = SyntheticEquipment.column(x: 200, z: 300, bottom: 0, top: 180, total: 80)
        let modifier = SyntheticEquipment.column(x: 230, z: 300, bottom: 200, top: 220, total: 20)

        let result = Geometry.centres(of: stand + modifier, floorY: 0, isSubject: false)

        #expect(result.status == .measured)
        let base = try #require(result.baseCentre)
        let top = try #require(result.topCentre)
        #expect(near(top.y, cm(220), cm(2)))
        #expect(near(SIMD2(top.x, top.z), SIMD2(cm(230), cm(300)), cm(1)))
        #expect(near(base, SIMD2(cm(200), cm(300)), cm(2)))
    }

    @Test("A floor that is not at zero gives the same result as a floor at zero")
    func floorNotAtZero() throws {
        let points = SyntheticEquipment.shifted(equipment(bottom: 0, top: 180), dy: -120)

        let result = Geometry.centres(of: points, floorY: cm(-120), isSubject: false)

        #expect(result.status == .measured)
        let base = try #require(result.baseCentre)
        let top = try #require(result.topCentre)
        #expect(near(base, SIMD2(cm(200), cm(300)), cm(1)))
        #expect(near(top, SIMD3(cm(200), cm(-120 + 180), cm(300)), cm(1)))
    }

    @Test("The base ignores a part that sticks out higher up")
    func baseIgnoresPartStickingOut() throws {
        let stand = SyntheticEquipment.column(x: 200, z: 300, bottom: 0, top: 180, total: 60)
        let boom = SyntheticEquipment.column(x: 260, z: 300, bottom: 100, top: 180, total: 40, capCount: 0)

        let result = Geometry.centres(of: stand + boom, floorY: 0, isSubject: false)

        #expect(result.status == .measured)
        let base = try #require(result.baseCentre)
        #expect(near(base, SIMD2(cm(200), cm(300)), cm(1)))
    }

    // MARK: Base not seen

    @Test("An item floating above the floor is base not seen")
    func floatingItem() {
        let result = Geometry.centres(of: equipment(bottom: 50, top: 180), floorY: 0, isSubject: false)

        #expect(result.status == .baseNotSeen)
        #expect(result.baseCentre == nil)
        #expect(result.topCentre == nil)
    }

    @Test("The gap boundary: 15 cm is measured, 16 cm is base not seen")
    func gapBoundary() {
        let atLimit = Geometry.centres(of: equipment(bottom: 15, top: 195), floorY: 0, isSubject: false)
        let overLimit = Geometry.centres(of: equipment(bottom: 16, top: 196), floorY: 0, isSubject: false)

        #expect(atLimit.status == .measured)
        #expect(overLimit.status == .baseNotSeen)
    }

    // MARK: Too few points

    @Test("99 points is too few points")
    func belowMinimum() {
        let result = Geometry.centres(of: equipment(bottom: 0, top: 180, total: 99), floorY: 0, isSubject: false)

        #expect(result.status == .tooFewPoints)
        #expect(result.baseCentre == nil)
        #expect(result.topCentre == nil)
    }

    @Test("Exactly 100 points is measured")
    func atMinimum() {
        let result = Geometry.centres(of: equipment(bottom: 0, top: 180, total: 100), floorY: 0, isSubject: false)

        #expect(result.status == .measured)
    }

    @Test("No points is too few points, without a crash")
    func noPoints() {
        let result = Geometry.centres(of: [], floorY: 0, isSubject: false)

        #expect(result.status == .tooFewPoints)
        #expect(result.baseCentre == nil)
        #expect(result.topCentre == nil)
    }

    @Test("Too few points wins over base not seen")
    func tooFewBeatsFloating() {
        let result = Geometry.centres(of: equipment(bottom: 50, top: 180, total: 50), floorY: 0, isSubject: false)

        #expect(result.status == .tooFewPoints)
    }

    // MARK: Noise

    @Test("One stray point above and to the side does not move the top")
    func strayPointAbove() throws {
        let stray = SIMD3<Float>(cm(260), cm(280), cm(300))   // 100 cm above the real top at 180, and 60 cm to the side
        let result = Geometry.centres(of: equipment(bottom: 0, top: 180) + [stray], floorY: 0, isSubject: false)

        #expect(result.status == .measured)
        let top = try #require(result.topCentre)
        #expect(near(top.y, cm(180), cm(2)))
        #expect(near(SIMD2(top.x, top.z), SIMD2(cm(200), cm(300)), cm(1)))
    }

    @Test("Two stray points above do not move the top")
    func twoStrayPointsAbove() throws {
        let strays = [SIMD3<Float>(cm(200), cm(280), cm(300)), SIMD3<Float>(cm(200), cm(290), cm(300))]
        // 98 item points + 2 strays = 100 points, so the top 2% are exactly the strays.
        let result = Geometry.centres(of: equipment(bottom: 0, top: 180, total: 98) + strays, floorY: 0, isSubject: false)

        #expect(result.status == .measured)
        let top = try #require(result.topCentre)
        #expect(near(top.y, cm(180), cm(2)))
    }

    // MARK: Subject

    @Test("The subject on a table is measured from the product's bottom")
    func subjectOnTable() throws {
        let result = Geometry.centres(of: equipment(bottom: 75, top: 95), floorY: 0, isSubject: true)

        #expect(result.status == .measured)
        let base = try #require(result.baseCentre)
        let top = try #require(result.topCentre)
        #expect(near(base, SIMD2(cm(200), cm(300)), cm(1)))
        #expect(near(top.y, cm(95), cm(1)))
    }

    @Test("The same table-height points are base not seen for a normal item")
    func sameItemNotSubject() {
        let result = Geometry.centres(of: equipment(bottom: 75, top: 95), floorY: 0, isSubject: false)

        #expect(result.status == .baseNotSeen)
    }
}

/// A10-18 test cases. Distances in the written cases are whole centimetres; `cm(_:)` converts them to metres.
@Suite("Floor distance (A10-18)")
struct FloorDistanceTests {
    @Test("An item to the right of the subject is 100 cm away")
    func itemToTheRight() throws {
        let subject = measuredCentres(baseX: 200, baseZ: 300)
        let light = measuredCentres(baseX: 300, baseZ: 300)

        let distance = try #require(Geometry.floorDistance(from: subject, to: light))

        #expect(near(distance, cm(100), 0.001))
    }

    @Test("A 3-4-5 diagonal is 500 cm away")
    func diagonal() throws {
        let subject = measuredCentres(baseX: 0, baseZ: 0)
        let light = measuredCentres(baseX: 300, baseZ: 400)

        let distance = try #require(Geometry.floorDistance(from: subject, to: light))

        #expect(near(distance, cm(500), 0.001))
    }

    @Test("Height is ignored")
    func heightIsIgnored() throws {
        let subject = measuredCentres(baseX: 200, baseZ: 300, topY: 95)
        let light = measuredCentres(baseX: 300, baseZ: 300, topY: 180)

        let distance = try #require(Geometry.floorDistance(from: subject, to: light))

        #expect(near(distance, cm(100), 0.001))
    }

    @Test("A light at the same spot as the subject is 0 cm away")
    func sameSpot() throws {
        let subject = measuredCentres(baseX: 200, baseZ: 300)
        let light = measuredCentres(baseX: 200, baseZ: 300)

        let distance = try #require(Geometry.floorDistance(from: subject, to: light))

        #expect(near(distance, 0, 0.001))
    }

    @Test("A light whose base centre is missing is not measured")
    func itemBaseMissing() {
        let subject = measuredCentres(baseX: 200, baseZ: 300)

        #expect(Geometry.floorDistance(from: subject, to: baseNotSeenCentres()) == nil)
    }

    @Test("A subject whose base centre is missing is not measured")
    func subjectBaseMissing() {
        let light = measuredCentres(baseX: 300, baseZ: 300)

        #expect(Geometry.floorDistance(from: baseNotSeenCentres(), to: light) == nil)
    }
}
