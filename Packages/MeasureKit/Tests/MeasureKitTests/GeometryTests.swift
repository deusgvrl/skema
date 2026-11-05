import Testing
import simd
@testable import MeasureKit

@Suite struct GeometryTests {
    @Test func medianIgnoresOneFarOutlier() {
        let pts: [SIMD3<Float>] = [SIMD3(1, 1, 1), SIMD3(1.1, 1.1, 1.1), SIMD3(0.9, 0.9, 0.9),
                                   SIMD3(1.05, 1.05, 1.05), SIMD3(100, 100, 100)]
        let m = Geometry.medianPoint(pts)!
        #expect(near(m, SIMD3(1.05, 1.05, 1.05)))
        #expect(Geometry.medianPoint([]) == nil)
    }

    @Test func principalAxisOfVerticalLine() {
        let pts = (0..<10).map { SIMD3<Float>(0.3, Float($0) * 0.1, -1) }
        let axis = Geometry.principalAxis(pts)!
        #expect(near(axis, SIMD3(0, 1, 0)))
    }

    @Test func principalAxisOf45DegreeLineGivesTilt45() {
        let pts = (0..<10).map { SIMD3<Float>(Float($0) * 0.1, Float($0) * 0.1, -1) }
        let axis = Geometry.principalAxis(pts)!
        #expect(axis.y >= 0)
        #expect(abs(Geometry.tiltDegrees(axis: axis) - 45) < 0.5)
    }

    @Test func principalAxisNilForTooFewPoints() {
        #expect(Geometry.principalAxis([]) == nil)
        #expect(Geometry.principalAxis([SIMD3(0, 0, 0), SIMD3(0, 1, 0)]) == nil)
    }

    @Test func principalAxisNilWithoutDominantDirection() {
        // A flat square grid: both in-plane eigenvalues are equal.
        var pts: [SIMD3<Float>] = []
        for i in 0..<5 { for j in 0..<5 { pts.append(SIMD3(Float(i), Float(j), 0)) } }
        #expect(Geometry.principalAxis(pts) == nil)
    }

    @Test func tiltDegrees() {
        #expect(abs(Geometry.tiltDegrees(axis: SIMD3(0, 1, 0))) < 0.5)
        #expect(abs(Geometry.tiltDegrees(axis: SIMD3(1, 0, 0)) - 90) < 0.5)
        #expect(abs(Geometry.tiltDegrees(axis: SIMD3(0, -1, 0))) < 0.5)
        let a = Geometry.tiltDegrees(axis: SIMD3(1, 1, 0))
        let b = Geometry.tiltDegrees(axis: SIMD3(-1, -1, 0))
        #expect(abs(a - b) < 1e-4)
    }

    @Test func aimOffsetDegrees() {
        let from = SIMD3<Float>(0, 0, 0)
        let toX = SIMD3<Float>(5, 0, 0)
        let toZ = SIMD3<Float>(0, 0, 5)
        #expect(abs(Geometry.aimOffsetDegrees(axis: SIMD3(1, 0, 0), from: from, to: toX)! - 0) < 0.5)
        #expect(abs(Geometry.aimOffsetDegrees(axis: SIMD3(1, 0, 0), from: from, to: toZ)! - 90) < 0.5)
        #expect(abs(Geometry.aimOffsetDegrees(axis: SIMD3(-1, 0, 0), from: from, to: toX)! - 0) < 0.5)
        #expect(abs(Geometry.aimOffsetDegrees(axis: SIMD3(1, 0, 1), from: from, to: toX)! - 45) < 0.5)
        #expect(Geometry.aimOffsetDegrees(axis: SIMD3(0, 1, 0), from: from, to: toX) == nil)
        // About 10° from vertical: below minAimTiltDegrees, so no aim.
        #expect(Geometry.aimOffsetDegrees(axis: simd_normalize(SIMD3(0.17, 1, 0)), from: from, to: toX) == nil)
        // Target straight above the object has no horizontal direction.
        #expect(Geometry.aimOffsetDegrees(axis: SIMD3(1, 0, 0), from: from, to: SIMD3(0, 3, 0)) == nil)
    }

    @Test func aimNeedsAtLeastMinAimTilt() {
        // Review finding 4: at small tilts the horizontal direction is LiDAR noise, so no aim.
        func axis(tilt degrees: Float) -> SIMD3<Float> {
            let r = degrees * .pi / 180
            return SIMD3(sin(r), cos(r), 0)
        }
        let from = SIMD3<Float>(0, 0, 0), to = SIMD3<Float>(5, 0, 0)
        #expect(Geometry.aimOffsetDegrees(axis: axis(tilt: 15), from: from, to: to) == nil)
        #expect(Geometry.aimOffsetDegrees(axis: axis(tilt: Geometry.minAimTiltDegrees - 0.5), from: from, to: to) == nil)
        #expect(Geometry.aimOffsetDegrees(axis: axis(tilt: Geometry.minAimTiltDegrees + 0.5), from: from, to: to) != nil)
    }

    @Test func heightAboveFloor() {
        #expect(near(Geometry.heightAboveFloor(SIMD3(1, 0.8, 2), floorY: -0.2), 1.0))
    }
}
