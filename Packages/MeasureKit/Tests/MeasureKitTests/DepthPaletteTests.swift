import Testing
import simd
@testable import MeasureKit

@Suite struct DepthPaletteTests {
    @Test func fourStopsExact() {
        #expect(DepthPalette.rgb(0) == SIMD3<UInt8>(255, 0, 0))
        #expect(DepthPalette.rgb(1.0 / 3) == SIMD3<UInt8>(255, 255, 0))
        #expect(DepthPalette.rgb(2.0 / 3) == SIMD3<UInt8>(0, 255, 0))
        #expect(DepthPalette.rgb(1) == SIMD3<UInt8>(0, 0, 255))
    }

    @Test func linearBetweenStops() {
        #expect(DepthPalette.rgb(1.0 / 6) == SIMD3<UInt8>(255, 128, 0))   // red -> yellow, halfway
    }

    @Test func clampedOutsideRange() {
        #expect(DepthPalette.rgb(-5) == SIMD3<UInt8>(255, 0, 0))
        #expect(DepthPalette.rgb(7) == SIMD3<UInt8>(0, 0, 255))
    }
}
