import Testing
@testable import MeasureKitVision

@Suite struct LabelPickerTests {
    let targets: Set<String> = ["bottle", "cup"]

    @Test func picksBestTargetLabel() {
        let r = LabelPicker.pick([("cup", 0.5), ("bottle", 0.8), ("cup", 0.4)], targets: targets, minConfidence: 0.3)
        #expect(r?.label == "bottle")
        #expect(r?.confidence == 0.8)
    }

    @Test func ignoresHigherNonTargetLabels() {
        let r = LabelPicker.pick([("table", 0.99), ("cup", 0.35)], targets: targets, minConfidence: 0.3)
        #expect(r?.label == "cup")
    }

    @Test func nilBelowMinConfidence() {
        #expect(LabelPicker.pick([("cup", 0.2)], targets: targets, minConfidence: 0.3) == nil)
    }

    @Test func nilWhenNoTargetPresent() {
        #expect(LabelPicker.pick([("table", 0.9)], targets: targets, minConfidence: 0.3) == nil)
        #expect(LabelPicker.pick([], targets: targets, minConfidence: 0.3) == nil)
    }
}
