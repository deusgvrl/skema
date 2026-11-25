import Testing
import CoreGraphics
@testable import Skema_Photo

@Suite("Diagram canvas fits every item (A10-98)")
struct DiagramCanvasTests {
    private let base = CGSize(width: 523, height: 400)

    @Test("No items: the canvas stays the base size")
    func noItemsKeepsBase() {
        #expect(DiagramCanvas.size(fitting: [], base: base) == base)
    }

    @Test("Items close to the subject: the canvas stays the base size")
    func closeItemsKeepBase() {
        let offsets = [CGPoint(x: 120, y: -80), CGPoint(x: 0, y: 100)]
        #expect(DiagramCanvas.size(fitting: offsets, base: base) == base)
    }

    @Test("A far item grows the canvas so it fits, keeping the box's shape")
    func farItemGrowsCanvas() {
        // 600 pt to the right needs a half-width of 600 + padding.
        let size = DiagramCanvas.size(fitting: [CGPoint(x: 600, y: 0)], base: base)
        #expect(size.width == 2 * (600 + DiagramCanvas.itemPadding))
        #expect(abs(size.width / size.height - base.width / base.height) < 0.0001)
    }

    @Test("A far item below the subject grows the canvas by height")
    func farItemBelowGrowsCanvas() {
        let size = DiagramCanvas.size(fitting: [CGPoint(x: 0, y: 450)], base: base)
        #expect(size.height == 2 * (450 + DiagramCanvas.itemPadding))
        #expect(size.width > base.width)
    }
}

/// What VoiceOver says for equipment on the diagram. 2fc4f9d removed it; the copy audit (25 Nov) brings it back.
@MainActor
@Suite("Diagram equipment for VoiceOver")
struct DiagramEquipmentVoiceOverTests {
    @Test("The label is the name, then the role when there is one", arguments: [
        ("Light 1", "Key", "Light 1, Key"),
        ("Light 1", " ", "Light 1"),
        ("", "Key", "Key"),
        ("", "", "Light")
    ])
    func label(name: String, role: String, expected: String) {
        #expect(Equipment(category: .light, name: name, role: role).displayName == expected)
    }

    @Test("The value says how far from the subject and how it is turned", arguments: [
        ("2.0", 45.0, "2.0 meters from the subject, rotated 45 degrees"),
        ("1", 0.0, "1 meter from the subject, rotated 0 degrees"),
        (" ", 90.0, "Rotated 90 degrees"),
        ("1.50", 359.7, "1.50 meters from the subject, rotated 0 degrees")
    ])
    func value(distance: String, rotation: Double, expected: String) {
        let light = Equipment(category: .light, name: "Light 1", distance: distance, rotationAngle: rotation)

        #expect(light.spokenPosition == expected)
    }
}
