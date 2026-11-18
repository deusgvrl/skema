import Testing
import simd
@testable import MeasureKit

/// A10-90 rule E: small box, big box, and same-or-new by share inside (cases D24–D35).
@Suite struct DuplicateLightTests {
    private let light = "studio lighting"

    // MARK: Small box

    /// Dots evenly spread from 0 to the size on each axis, nothing piled on the edges (Case D24).
    private func evenDots(width: Float = 40, height: Float = 60, depth: Float = 10) -> [SIMD3<Float>] {
        let count = 201
        return (0..<count).map { index in
            let share = Float(index) / Float(count - 1)
            return SIMD3(cm(width * share), cm(height * share), cm(depth * share))
        }
    }

    /// For D25 and D26: the same spread, but 5% of the dots sit on each edge, like dots on a light's faces,
    /// so the box edges are exact and a stray dot is the only thing that can move them.
    private func spread(_ extent: Float) -> [Float] {
        let middle = (1...180).map { extent * Float($0) / 181 }
        return Array(repeating: 0, count: 10) + middle + Array(repeating: extent, count: 10)
    }

    private func dots(width: Float = 40, height: Float = 60, depth: Float = 10) -> [SIMD3<Float>] {
        let xs = spread(width), ys = spread(height), zs = spread(depth)
        return xs.indices.map { SIMD3(cm(xs[$0]), cm(ys[$0]), cm(zs[$0])) }
    }

    @Test("Case D24: evenly spread dots over 40 x 60 x 10 cm give a box of about that size, give or take 3 cm")
    func smallBoxMatchesTheDots() throws {
        let box = try #require(WorldBox.around(evenDots()))
        let size = box.max - box.min
        #expect(abs(size.x - cm(40)) <= cm(3))   // 3 cm, because the end dots are thrown away
        #expect(abs(size.y - cm(60)) <= cm(3))
        #expect(abs(size.z - cm(10)) <= cm(3))
    }

    @Test("Case D25: one stray dot 1 m behind is not counted, the box stays about 10 cm deep")
    func strayDotIsIgnored() throws {
        let stray = SIMD3<Float>(cm(20), cm(30), cm(110))
        let box = try #require(WorldBox.around(dots() + [stray]))
        #expect(abs((box.max.z - box.min.z) - cm(10)) <= cm(2))
        // The same goes for a stray dot 1 m in front: each side is trimmed.
        let front = try #require(WorldBox.around(dots() + [SIMD3(cm(20), cm(30), cm(-100))]))
        #expect(abs((front.max.z - front.min.z) - cm(10)) <= cm(2))
    }

    @Test("Case D26: dots all at one depth give a box 2 cm deep, centred on them; a side of 2 cm or more stays")
    func flatDotsGetTwoCentimetresDepth() throws {
        let flat = dots(depth: 0).map { SIMD3($0.x, $0.y, cm(50)) }
        let box = try #require(WorldBox.around(flat))
        #expect(near(box.max.z - box.min.z, cm(2)))
        #expect(near((box.max.z + box.min.z) / 2, cm(50)))
        let thick = try #require(WorldBox.around(dots(depth: 3)))
        #expect(near(thick.max.z - thick.min.z, cm(3), cm(0.1)))
    }

    // MARK: Big box

    @Test("Case D27: a new light's big box equals its first sighting's small box")
    func firstSightingIsTheBigBox() {
        var map = ObjectMap()
        let small = boxCm(x: 0...40, y: 0...60, z: 0...10)
        map.add([sighting(light, in: small)])
        #expect(map.objects[0].box == small)
    }

    @Test("Case D28: a big box 0 to 40 cm wide grows to 0 to 60 cm when a sighting from 20 to 60 cm joins")
    func bigBoxGrowsWithJoiningSightings() {
        var map = ObjectMap()
        map.add([sighting(light, in: boxCm(x: 0...40, y: 0...60, z: 0...10))])
        map.add([sighting(light, in: boxCm(x: 20...60, y: 0...60, z: 0...10))])
        #expect(map.objects.count == 1)
        #expect(map.objects[0].box == boxCm(x: 0...60, y: 0...60, z: 0...10))
    }

    @Test("Case D29: after 30 sightings the first is forgotten and the big box no longer reaches 50 cm left")
    func oldestSightingIsForgotten() {
        var map = ObjectMap()
        map.add([sighting(light, in: boxCm(x: -50...40, y: 0...50, z: 0...50))])
        for _ in 1..<ObjectMap.maxKeptSightings { map.add([sighting(light, in: boxCm(x: -10...40, y: 0...50, z: 0...50))]) }
        #expect(map.objects.count == 1)
        #expect(near(map.objects[0].box.min.x, cm(-50)))
        map.add([sighting(light, in: boxCm(x: -10...40, y: 0...50, z: 0...50))])
        #expect(map.objects.count == 1)
        #expect(near(map.objects[0].box.min.x, cm(-10)))
    }

    // MARK: Same or new

    private let big = boxCm(x: 0...60, y: 0...60, z: 0...60)

    @Test("Case D30: a sighting fully inside the item's big box joins it (share 100%)")
    func boxInsideJoins() {
        var map = ObjectMap()
        map.add([sighting(light, in: big), sighting(light, in: boxCm(x: 10...30, y: 10...30, z: 10...30))])
        #expect(map.objects.count == 1)
    }

    @Test("Case D31: a sighting whose box does not touch the item's big box is a new item (share 0%)")
    func boxApartIsNew() {
        var map = ObjectMap()
        map.add([sighting(light, in: big), sighting(light, in: boxCm(x: 100...160, y: 0...60, z: 0...60))])
        #expect(map.objects.count == 2)
    }

    @Test("Case D32: shares of 34% and 35%: 34% starts a new item, 35% joins")
    func thirtyFiveJoinsThirtyFourDoesNot() {
        // 1 m cubes sliding along x. The item's box runs 0 to 1; a sighting ending at `end` shares `end`.
        func fixture(share: Float) -> (item: WorldBox, other: WorldBox) {
            (WorldBox(min: .zero, max: SIMD3(1, 1, 1)),
             WorldBox(min: SIMD3(share - 1, 0, 0), max: SIMD3(share, 1, 1)))
        }
        let edge = fixture(share: ObjectMap.minShare)
        #expect(edge.item.shareInside(edge.other) == ObjectMap.minShare)   // the fixture really is at the limit
        var joins = ObjectMap()
        joins.add([sighting(light, in: edge.item), sighting(light, in: edge.other)])
        #expect(joins.objects.count == 1)
        let below = fixture(share: 0.34)
        var apart = ObjectMap()
        apart.add([sighting(light, in: below.item), sighting(light, in: below.other)])
        #expect(apart.objects.count == 2)
    }

    @Test("Case D33: a 40 cm sighting that holds a 10 cm item joins it (share is measured on the smaller box)")
    func largerBoxHoldingTheItemJoins() {
        var map = ObjectMap()
        map.add([sighting(light, in: boxCm(x: 0...10, y: 0...10, z: 0...10)),
                 sighting(light, in: boxCm(x: -15...25, y: -15...25, z: -15...25))])
        #expect(map.objects.count == 1)
    }

    @Test("Case D34: a light inside an accepted camera's big box does not join the camera, it starts a new item")
    func otherLabelNeverJoins() {
        var map = ObjectMap()
        for index in 0...10 { map.update([sighting("camera", in: big)], at: Double(index) / 10) }
        #expect(map.items.map(\.status) == [.accepted])
        map.update([sighting(light, in: boxCm(x: 10...30, y: 10...30, z: 10...30))], at: 1.1)
        #expect(map.items.map(\.label) == ["camera", light])
    }

    @Test("Case D35: big boxes holding 40% and 70% of a new sighting: it joins the 70% one")
    func highestShareWins() {
        var map = ObjectMap()
        let first = boxCm(x: -60...40, y: 0...10, z: 0...10)     // holds 40% of the new sighting
        let second = boxCm(x: 30...130, y: 0...10, z: 0...10)    // holds 70%
        map.add([sighting(light, in: first), sighting(light, in: second)])
        #expect(map.objects.count == 2)
        map.add([sighting(light, in: boxCm(x: 0...100, y: 0...10, z: 0...10))])
        #expect(map.objects.map(\.sightingCount) == [1, 2])
    }
}
