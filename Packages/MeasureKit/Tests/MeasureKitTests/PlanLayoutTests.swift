import Testing
import XCTest
import simd
@testable import MeasureKit

private func near2(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ tol: Float = 1e-4) -> Bool { simd_length(a - b) < tol }

final class PlanLayoutTests: XCTestCase {
    private let subject = SIMD3<Float>(1, 0.5, 2)

    func testViewerAlongPlusZ() {
        let viewer = subject + SIMD3(0, 0, 3)
        XCTAssertTrue(near2(PlanLayout.planPoint(subject + SIMD3(1, 0, 0), subject: subject, viewer: viewer), SIMD2(1, 0)))
        XCTAssertTrue(near2(PlanLayout.planPoint(subject + SIMD3(0, 0, 1), subject: subject, viewer: viewer), SIMD2(0, 1)))
        XCTAssertTrue(near2(PlanLayout.planPoint(viewer, subject: subject, viewer: viewer), SIMD2(0, 3)))
    }

    func testViewerAlongPlusX() {
        let viewer = subject + SIMD3(2, 0, 0)
        XCTAssertTrue(near2(PlanLayout.planPoint(subject + SIMD3(0, 0, -1), subject: subject, viewer: viewer), SIMD2(1, 0)))
    }

    func testHeightIsIgnored() {
        let viewer = subject + SIMD3(0, 0, 3)
        XCTAssertTrue(near2(PlanLayout.planPoint(subject + SIMD3(1, 9, 0), subject: subject, viewer: viewer), SIMD2(1, 0)))
        XCTAssertTrue(near2(PlanLayout.planPoint(subject, subject: subject, viewer: viewer + SIMD3(0, 5, 0)), .zero))
    }

    func testDegenerateViewerUsesPlusZ() {
        let viewer = subject + SIMD3(0, 2, 0)
        XCTAssertTrue(near2(PlanLayout.planPoint(subject + SIMD3(1, 0, 0), subject: subject, viewer: viewer), SIMD2(1, 0)))
        XCTAssertTrue(near2(PlanLayout.planPoint(subject + SIMD3(0, 0, 1), subject: subject, viewer: viewer), SIMD2(0, 1)))
    }

    func testPlanDirectionMatchesPlanPointRotation() throws {
        let viewer = subject + SIMD3(2, 0, 0)
        let d = try XCTUnwrap(PlanLayout.planDirection(SIMD3(0, 1, -1), subject: subject, viewer: viewer))
        XCTAssertTrue(near2(d, SIMD2(1, 0)))
        let e = try XCTUnwrap(PlanLayout.planDirection(SIMD3(3, 0, 0), subject: subject, viewer: viewer))
        XCTAssertTrue(near2(e, SIMD2(0, 1)))
    }

    func testVerticalAxisHasNoPlanDirection() {
        XCTAssertNil(PlanLayout.planDirection(SIMD3(0, 1, 0), subject: subject, viewer: subject + SIMD3(0, 0, 1)))
        XCTAssertNil(PlanLayout.planDirection(SIMD3(0.0005, 1, 0), subject: subject, viewer: subject + SIMD3(0, 0, 1)))
    }

    func testScaleFitsFarthestPointInsideMargin() {
        // half-extents 100 x 50 minus margin 10 = 90 x 40; farthest needs x 2 m -> 45, y 1 m -> 40
        let s = PlanLayout.scale(fitting: [SIMD2(2, 0), SIMD2(0, 1)], in: SIMD2(200, 100), margin: 10)
        XCTAssertEqual(s, 40, accuracy: 1e-4)
        let t = PlanLayout.scale(fitting: [SIMD2(-4, 0.5)], in: SIMD2(200, 100), margin: 10)
        XCTAssertEqual(t, 22.5, accuracy: 1e-4)
    }

    func testScaleCapsAtMaxScale() {
        XCTAssertEqual(PlanLayout.scale(fitting: [SIMD2(0.01, 0)], in: SIMD2(200, 100), margin: 10), 400)
        XCTAssertEqual(PlanLayout.scale(fitting: [SIMD2(0.01, 0)], in: SIMD2(200, 100), margin: 10, maxScale: 50), 50)
    }

    func testScaleWithNoPointsIsMaxScale() {
        XCTAssertEqual(PlanLayout.scale(fitting: [], in: SIMD2(200, 100), margin: 10), 400)
        XCTAssertEqual(PlanLayout.scale(fitting: [.zero], in: SIMD2(200, 100), margin: 10, maxScale: 80), 80)
    }
}

/// A10-62 follow-up: a floor offset (x, z of equipment minus subject, metres) turned into plan axes.
@Suite("Plan offset")
struct PlanOffsetTests {
    private func close(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Bool { simd_length(a - b) < 1e-4 }

    @Test("Phone on the +z side of the subject: the offset is unchanged (plan down is +z)")
    func phoneAlongPlusZ() {
        #expect(close(PlanLayout.planOffset(SIMD2(1, 0), towardViewer: SIMD2(0, 3)), SIMD2(1, 0)))
        #expect(close(PlanLayout.planOffset(SIMD2(0, 1), towardViewer: SIMD2(0, 3)), SIMD2(0, 1)))
    }

    @Test("Phone on the +x side: world -z becomes plan right, world +x becomes plan down")
    func phoneAlongPlusX() {
        #expect(close(PlanLayout.planOffset(SIMD2(0, -1), towardViewer: SIMD2(2, 0)), SIMD2(1, 0)))
        #expect(close(PlanLayout.planOffset(SIMD2(1, 0), towardViewer: SIMD2(2, 0)), SIMD2(0, 1)))
    }

    @Test("The length does not depend on how far the phone is")
    func distanceOfThePhoneDoesNotMatter() {
        #expect(close(PlanLayout.planOffset(SIMD2(0, -1), towardViewer: SIMD2(20, 0)), SIMD2(1, 0)))
    }

    @Test("A phone right over the subject falls back to +z, like planPoint")
    func phoneOnTheSubject() {
        #expect(close(PlanLayout.planOffset(SIMD2(1, 2), towardViewer: .zero), SIMD2(1, 2)))
    }
}
