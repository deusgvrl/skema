import Foundation
import MeasureKit
import Testing

/// Scan screen phase 3 (team decision, 24 Nov 2026): an item is done once the phone has seen it from two spots at
/// least 45° apart around it, seen from above.
@Suite("View spread: how far around an item it was seen")
struct ViewSpreadTests {
    /// An item at the origin; a spot `metres` away at `degrees` around it (0° along +x, 90° along +z).
    private func spot(_ degrees: Float, metres: Float = 2) -> SIMD3<Float> {
        let radians = degrees * .pi / 180
        return SIMD3(cos(radians) * metres, 1.4, sin(radians) * metres)
    }

    private func spread(_ spots: [SIMD3<Float>]) -> ViewSpread {
        var spread = ViewSpread()
        for spot in spots { spread.add(from: spot, around: .zero) }
        return spread
    }

    @Test("Nothing seen yet, or one spot only: no spread, not enough")
    func oneSpot() {
        #expect(ViewSpread().degrees == 0)
        #expect(spread([spot(30), spot(30), spot(30)]).degrees < 1e-3)
        #expect(!spread([spot(30)]).isEnough)
    }

    @Test("Two spots 45° apart are enough; 40° apart are not")
    func fortyFive() {
        #expect(abs(spread([spot(10), spot(55)]).degrees - 45) < 0.01)
        #expect(spread([spot(10), spot(55)]).isEnough)
        #expect(!spread([spot(10), spot(50)]).isEnough)
    }

    @Test("Spots on both sides of the first one add up")
    func bothSides() {
        #expect(abs(spread([spot(0), spot(-25), spot(25)]).degrees - 50) < 0.01)
    }

    @Test("Walking past the back (170° to -170°) is 20°, not 340°")
    func wrapsAround() {
        #expect(abs(spread([spot(170), spot(-170)]).degrees - 20) < 0.01)
    }

    @Test("Height doesn't count: the same spot higher or lower adds nothing")
    func heightIgnored() {
        var high = spot(30)
        high.y = 2.5
        #expect(spread([spot(30), high]).degrees < 1e-3)
    }

    @Test("A spot straight above the item (closer than 20 cm, seen from above) is ignored")
    func tooCloseIgnored() {
        #expect(spread([spot(0), spot(90, metres: 0.1)]).degrees < 1e-3)
        #expect(spread([spot(90, metres: 0.1), spot(0), spot(50)]).isEnough)
    }
}
