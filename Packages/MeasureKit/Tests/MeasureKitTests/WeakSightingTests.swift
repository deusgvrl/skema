import Testing
import simd
@testable import MeasureKit

/// A10-90 cases D21–D22: which items a weak sighting may keep alive.
@Suite struct WeakSightingTests {
    private func light(_ x: Float = 0) -> Sighting {
        Sighting(label: "studio lighting", confidence: 0.4, position: SIMD3(x, 0, 0), axis: nil, pointCount: 50)
    }

    private func mapWithLight(accepted: Bool) -> ObjectMap {
        var map = ObjectMap()
        // Seen for 1 s makes it accepted; 0.5 s leaves it pending.
        for index in 0...(accepted ? 10 : 5) { map.update([light()], at: Double(index) / 10) }
        return map
    }

    @Test("Case D21: a sighting within 20 cm of an accepted light of the same label can keep it")
    func nearAcceptedLightCounts() {
        let map = mapWithLight(accepted: true)
        #expect(map.hasAcceptedObject(near: light(0.19)))
        #expect(!map.hasAcceptedObject(near: light(0.21)))
    }

    @Test("Case D22: a pending light, another label, or no item at all does not count")
    func pendingOrOtherLabelDoesNotCount() {
        #expect(!mapWithLight(accepted: false).hasAcceptedObject(near: light()))
        #expect(!ObjectMap().hasAcceptedObject(near: light()))
        let camera = Sighting(label: "camera", confidence: 0.4, position: .zero, axis: nil, pointCount: 50)
        #expect(!mapWithLight(accepted: true).hasAcceptedObject(near: camera))
    }
}
