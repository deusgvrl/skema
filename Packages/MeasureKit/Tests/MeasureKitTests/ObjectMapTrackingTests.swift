import Foundation
import Testing
import simd
@testable import MeasureKit

/// A10-61 test cases 1–9 (docs/test-cases/A10-61_item-tracking.md in the Challenge 5 folder).
/// The detector looks every 0.1 s: look i happens at i / 10 seconds.
private func look(_ index: Int) -> TimeInterval { TimeInterval(index) / 10 }

private func light(_ x: Float = 0) -> Sighting {
    Sighting(label: "studio lighting", confidence: 0.6, position: SIMD3(x, 0, 0), axis: nil, pointCount: 50)
}

private func camera(_ x: Float = 0) -> Sighting {
    Sighting(label: "camera", confidence: 0.6, position: SIMD3(x, 0, 0), axis: nil, pointCount: 50)
}

@Suite struct ObjectMapTrackingTests {
    // Case 1.
    @Test func itemSeenForLessThanOneSecondIsPendingWithoutNumber() {
        var map = ObjectMap()
        for index in 0...9 { map.update([light()], at: look(index)) }
        #expect(map.items.map(\.status) == [.pending])
        #expect(map.items.first?.number == nil)
    }

    // Case 2.
    @Test func itemSeenForOneSecondIsAcceptedWithNumberOne() {
        var map = ObjectMap()
        for index in 0...10 { map.update([light()], at: look(index)) }
        #expect(map.items.map(\.status) == [.accepted])
        #expect(map.items.first?.number == 1)
    }

    // Case 3. Missed at 0.6 s: the wait 0.5 → 0.6 doesn't count, so 1 s is reached at 1.1 s, not 1.0 s.
    @Test func shortGapIsAllowedButNotCounted() {
        var map = ObjectMap()
        for index in 0...5 { map.update([light()], at: look(index)) }
        map.update([], at: look(6))
        for index in 7...10 { map.update([light()], at: look(index)) }
        #expect(map.items.map(\.status) == [.pending])
        map.update([light()], at: look(11))
        #expect(map.items.map(\.status) == [.accepted])
    }

    // Case 4. Last seen at 0.5 s: 0.2 s later (0.7 s) is still allowed, 0.3 s later (0.8 s) removes the flicker.
    // The flicker never took a number, so the light found again is number 1.
    @Test func longGapRemovesAPendingItemWithoutUsingANumber() {
        var map = ObjectMap()
        for index in 0...5 { map.update([light()], at: look(index)) }
        map.update([], at: look(6))
        map.update([], at: look(7))
        #expect(map.items.count == 1)
        map.update([], at: look(8))
        #expect(map.items.isEmpty)
        for index in 9...19 { map.update([light()], at: look(index)) }
        #expect(map.items.map(\.status) == [.accepted])
        #expect(map.items.first?.number == 1)
    }

    // Case 5.
    @Test func acceptedItemStaysWhenNotSeen() {
        var map = ObjectMap()
        for index in 0...10 { map.update([light()], at: look(index)) }
        for index in 11...200 { map.update([], at: look(index)) }
        #expect(map.items.map(\.status) == [.accepted])
    }

    // Cases 6 and 7.
    @Test func cameraWithinTwentyCentimetresIsTheSameItemFartherIsANewOne() {
        var map = ObjectMap()
        for index in 0...10 { map.update([camera(0)], at: look(index)) }
        for index in 11...21 { map.update([camera(0.15)], at: look(index)) }
        #expect(map.items.count == 1)
        #expect(map.items.first?.number == 1)
        for index in 22...32 { map.update([camera(1)], at: look(index)) }
        #expect(map.items.map(\.number) == [1, 2])
        #expect(map.items.map(\.status) == [.accepted, .accepted])
    }

    // Case 8. Accepted at 1.0 s (light), 1.3 s (camera) and 1.5 s (second light). Numbers count per kind.
    @Test func numbersCountPerKind() {
        var map = ObjectMap()
        for index in 0...15 {
            var seen = [light(0)]
            if index >= 3 { seen.append(camera(2)) }
            if index >= 5 { seen.append(light(4)) }
            map.update(seen, at: look(index))
        }
        #expect(map.items.map(\.label) == ["studio lighting", "camera", "studio lighting"])
        #expect(map.items.map(\.number) == [1, 1, 2])
    }

    // Case 9. The number after a delete is still open, so only the status is checked.
    @Test func forgottenItemStartsOverAsPending() throws {
        var map = ObjectMap()
        for index in 0...10 { map.update([light()], at: look(index)) }
        let id = try #require(map.items.first?.id)
        map.forget(id: id)
        #expect(map.items.isEmpty)
        for index in 11...20 { map.update([light()], at: look(index)) }
        #expect(map.items.map(\.status) == [.pending])
        map.update([light()], at: look(21))
        #expect(map.items.map(\.status) == [.accepted])
    }
}
