import Testing
@testable import MeasureKit

@Suite("MeasureKit")
struct MeasureKitTests {

    @Test("Package builds and links")
    func packageLinks() {
        #expect(MeasureKit.version == "0.1.0")
    }
}
