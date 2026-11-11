import Foundation
import Testing
import simd
@testable import MeasureKit

/// What tracking must tell the scan overlay (A10-62 cases 1, 2, 6–8 and 21, in the A10-62 Jira issue).
/// The detector looks every 0.1 s: look i happens at i / 10 seconds.
private func lookTime(_ index: Int) -> TimeInterval { TimeInterval(index) / 10 }

private func lightAt(_ x: Float) -> Sighting {
    Sighting(label: "studio lighting", confidence: 0.6, position: SIMD3(x, 0, 0), axis: nil, pointCount: 50)
}

private func cameraAt(_ x: Float) -> Sighting {
    Sighting(label: "Camera", confidence: 0.6, position: SIMD3(x, 0, 0), axis: nil, pointCount: 50)
}

@Suite struct ObjectMapOverlayInputTests {
    // A10-62 case 1: a light that was just found has an empty ring.
    @Test func justFoundItemHasNoProgress() {
        var map = ObjectMap()
        map.update([lightAt(0)], at: lookTime(0))
        #expect(map.items.first?.progress == 0)
    }

    // A10-62 case 2: seen for 0.5 s, the ring is half full.
    @Test func progressIsTheShareOfTheSecondSeen() throws {
        var map = ObjectMap()
        for index in 0...5 { map.update([lightAt(0)], at: lookTime(index)) }
        let progress = try #require(map.items.first?.progress)
        #expect(abs(progress - 0.5) < 1e-9)
    }

    // An accepted item's ring is full and stays full.
    @Test func acceptedItemHasFullProgress() {
        var map = ObjectMap()
        for index in 0...15 { map.update([lightAt(0)], at: lookTime(index)) }
        #expect(map.items.first?.progress == 1)
    }

    // A10-62 cases 6–8 and 21: a mask is drawn only for items seen at this look.
    @Test func itemIsMarkedSeenOnlyAtLooksThatSawIt() {
        var map = ObjectMap()
        map.update([lightAt(0)], at: lookTime(0))
        #expect(map.items.first?.isSeen == true)
        map.update([], at: lookTime(1))
        #expect(map.items.first?.isSeen == false)
    }

    // Masks come from the detector, items from tracking: update says which item each sighting joined, in order.
    @Test func updateTellsWhichItemEachSightingJoined() {
        var map = ObjectMap()
        let first = map.update([lightAt(0), cameraAt(2)], at: lookTime(0))
        let second = map.update([cameraAt(2.05), lightAt(0.05)], at: lookTime(1))
        #expect(first == [0, 1])
        #expect(second == [1, 0])
    }
}
