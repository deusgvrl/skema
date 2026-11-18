import Testing
import simd
@testable import MeasureKit

/// A10-90 cases D21, D22 and D36: which items a weak sighting (35–49%) may join.
@Suite struct WeakSightingTests {
    private let lightLabel = "studio lighting"

    private func light(_ box: WorldBox, weak: Bool = false) -> Sighting {
        sighting(lightLabel, in: box, confidence: weak ? 0.4 : 0.6, weak: weak)
    }

    /// Seen for 1 s makes a light accepted; 0.5 s leaves it pending. Looks run from `start`, 0.1 s apart.
    private func see(_ map: inout ObjectMap, _ box: WorldBox, looks: ClosedRange<Int>) {
        for index in looks { map.update([light(box)], at: Double(index) / 10) }
    }

    private let accepted = boxCm(x: 0...40, y: 0...40, z: 0...40)

    @Test("Case D21: a weak light at least 35% inside an accepted light joins it and counts as seen")
    func weakLightInsideAcceptedLightJoins() {
        var map = ObjectMap()
        see(&map, accepted, looks: 0...10)
        let before = map.objects[0].sightingCount
        let ids = map.update([light(boxCm(x: 20...60, y: 0...40, z: 0...40), weak: true)], at: 1.1)
        #expect(ids == [map.items[0].id])
        #expect(map.items.count == 1)
        #expect(map.items[0].isSeen)
        #expect(map.objects[0].sightingCount == before + 1)
    }

    @Test("Case D22: a weak light under 35% inside every accepted light makes no item, even inside a pending one")
    func weakLightOutsideAcceptedLightsMakesNothing() {
        var map = ObjectMap()
        see(&map, accepted, looks: 0...10)
        let pendingBox = boxCm(x: 200...240, y: 0...40, z: 0...40)
        see(&map, pendingBox, looks: 11...12)
        #expect(map.items.map(\.status) == [.accepted, .pending])
        let ids = map.update([light(pendingBox, weak: true)], at: 1.3)
        #expect(ids == [nil])
        #expect(map.items.count == 2)
        #expect(map.items[1].isSeen == false)
    }

    @Test("Case D22: a weak light alone starts no item and no clock")
    func weakLightAloneStartsNothing() {
        var map = ObjectMap()
        for index in 0...20 { map.update([light(accepted, weak: true)], at: Double(index) / 10) }
        #expect(map.items.isEmpty)
    }

    @Test("Case D36: a weak light 50% inside an accepted light and 90% inside a pending one joins the accepted one")
    func weakLightJoinsAcceptedEvenWhenPendingFitsBetter() {
        var map = ObjectMap()
        let acceptedBox = boxCm(x: 0...100, y: 0...10, z: 0...10)
        let pendingBox = boxCm(x: 114...154, y: 0...10, z: 0...10)
        let weakBox = boxCm(x: 50...150, y: 0...10, z: 0...10)
        see(&map, acceptedBox, looks: 0...10)
        see(&map, pendingBox, looks: 11...12)
        #expect(map.items.map(\.status) == [.accepted, .pending])
        let ids = map.update([light(weakBox, weak: true)], at: 1.3)
        #expect(ids == [map.items[0].id])
        #expect(map.items[0].isSeen)
        #expect(map.items[1].isSeen == false)
    }
}
