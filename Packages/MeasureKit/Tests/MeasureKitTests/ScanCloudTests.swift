import Testing
import simd
@testable import MeasureKit

@Suite struct ScanCloudTests {
    private func pt(_ x: Float, _ y: Float = 0, _ z: Float = 0, _ c: UInt8 = 0) -> (world: SIMD3<Float>, rgb: SIMD3<UInt8>) {
        (SIMD3(x, y, z), SIMD3(c, c, c))
    }

    @Test func firstPointInAVoxelWins() {
        var cloud = ScanCloud()
        let added = cloud.add([pt(0.101, 0, 0, 1), pt(0.105, 0, 0, 2)])   // same 1 cm voxel
        #expect(added.count == 1 && added[0].rgb == SIMD3(1, 1, 1))
        #expect(cloud.count == 1)
    }

    @Test func differentVoxelsBothAdded() {
        var cloud = ScanCloud()
        #expect(cloud.add([pt(0.101), pt(0.112)]).count == 2)
        #expect(cloud.count == 2 && cloud.allPoints.count == 2)
    }

    @Test func addReturnsOnlyNewPoints() {
        var cloud = ScanCloud()
        _ = cloud.add([pt(0.101)])
        let added = cloud.add([pt(0.103, 0, 0, 9), pt(0.5, 0, 0, 7)])
        #expect(added.count == 1 && added[0].rgb == SIMD3(7, 7, 7))
        #expect(cloud.count == 2)
    }

    @Test func negativeCoordinatesUseFloorVoxels() {
        var cloud = ScanCloud()
        // -0.004 and +0.004 straddle zero: different voxels.
        #expect(cloud.add([pt(-0.004), pt(0.004)]).count == 2)
    }

    @Test func stopsAtMaxPoints() {
        var cloud = ScanCloud(maxPoints: 3)
        let added = cloud.add((0..<5).map { pt(Float($0) * 0.05) })
        #expect(added.count == 3 && cloud.count == 3)
        #expect(cloud.add([pt(9)]).isEmpty)
        #expect(ScanCloud.maxPoints == 600_000 && ScanCloud.voxelSize == 0.01)
    }

    @Test func removeAllEmptiesAndFreesVoxels() {
        var cloud = ScanCloud()
        _ = cloud.add([pt(0.101)])
        cloud.removeAll()
        #expect(cloud.count == 0 && cloud.allPoints.isEmpty)
        #expect(cloud.add([pt(0.101)]).count == 1)
    }
}
