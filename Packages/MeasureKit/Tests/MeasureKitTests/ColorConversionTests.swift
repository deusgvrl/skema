import Testing
import simd
@testable import MeasureKit

@Suite struct ColorConversionTests {
    private func close(_ a: SIMD3<UInt8>, _ b: SIMD3<UInt8>, _ tol: Int = 2) -> Bool {
        (0..<3).allSatisfy { abs(Int(a[$0]) - Int(b[$0])) <= tol }
    }

    @Test func whiteAndBlack() {
        #expect(ColorConversion.rgb(y: 255, cb: 128, cr: 128) == SIMD3<UInt8>(255, 255, 255))
        #expect(ColorConversion.rgb(y: 0, cb: 128, cr: 128) == SIMD3<UInt8>(0, 0, 0))
    }

    @Test func knownRed() {
        // Full-range BT.601 for pure red: Y 76, Cb 85, Cr 255.
        #expect(close(ColorConversion.rgb(y: 76, cb: 85, cr: 255), SIMD3<UInt8>(255, 0, 0)))
    }

    @Test func clampsOutOfGamut() {
        #expect(ColorConversion.rgb(y: 0, cb: 0, cr: 0) == SIMD3<UInt8>(0, 135, 0))   // R and B underflow
        #expect(ColorConversion.rgb(y: 255, cb: 255, cr: 128) == SIMD3<UInt8>(255, 211, 255))   // R and B overflow, G does not
    }
}
