import Testing
@testable import MeasureKit

@Suite struct FloorPickerTests {
    @Test func tableOnlyGivesNoFloor() {
        // Review finding 3: a desk must never stand in for the floor.
        #expect(FloorPicker.floorY([HorizontalPlane(y: 0.75, isFloor: false)]) == nil)
    }

    @Test func picksLowestFloorAndIgnoresOtherPlanes() {
        let planes = [HorizontalPlane(y: 0.75, isFloor: false),
                      HorizontalPlane(y: -0.02, isFloor: true),
                      HorizontalPlane(y: 0.01, isFloor: true),
                      HorizontalPlane(y: -0.40, isFloor: false)]
        #expect(FloorPicker.floorY(planes) == -0.02)
    }

    @Test func noPlanesGivesNoFloor() {
        #expect(FloorPicker.floorY([]) == nil)
    }
}
