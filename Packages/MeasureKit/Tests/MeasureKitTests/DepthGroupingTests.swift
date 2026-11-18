import Testing
import simd
@testable import MeasureKit

/// A10-90 cases D10–D14 and D19 (written in the A10-90 Jira issue): grouping a mask by depth, the "paint bucket".
@Suite struct DepthGroupingTests {
    private func frame(_ width: Int, _ height: Int, _ depths: [Float], confidence: [UInt8]? = nil) -> DepthFrame {
        DepthFrame(width: width, height: height, depth: depths,
                   confidence: confidence ?? [UInt8](repeating: 2, count: depths.count))
    }

    private func full(_ width: Int, _ height: Int) -> InstanceMask {
        InstanceMask(width: width, height: height, pixels: [UInt8](repeating: 1, count: width * height))
    }

    @Test("Case D10: a camera at 1.50 m and a person at 2.00 m are two groups, nearest first")
    func cameraAndPersonAreTwoGroups() {
        let groups = DepthGrouping.groups(in: full(6, 1), depth: frame(6, 1, [1.50, 1.51, 1.52, 2.00, 2.01, 2.02]))
        #expect(groups.map(\.pixels) == [[1, 1, 1, 0, 0, 0], [0, 0, 0, 1, 1, 1]])
    }

    @Test("Case D10: a group keeps the mask's size when the mask is finer than the depth map")
    func groupKeepsTheMaskSize() {
        let groups = DepthGrouping.groups(in: full(4, 2), depth: frame(2, 1, [1.50, 2.00]))
        #expect(groups.first == InstanceMask(width: 4, height: 2, pixels: [1, 1, 0, 0, 1, 1, 0, 0]))
    }

    @Test("Case D11: a tilted softbox, 3 cm deeper per pixel, is one group and its mask is unchanged")
    func tiltedSoftboxStaysWhole() {
        let depths = (0..<14).map { 1.20 + 0.03 * Float($0) }
        #expect(DepthGrouping.groups(in: full(14, 1), depth: frame(14, 1, depths)) == [full(14, 1)])
    }

    @Test("Case D12: 4 cm between neighbours joins, 5 cm is an edge")
    func fourJoinsFiveIsAnEdge() {
        #expect(DepthGrouping.isSameSurface(0.50, 0.54))
        #expect(!DepthGrouping.isSameSurface(0.50, 0.55))
        #expect(!DepthGrouping.isSameSurface(0.55, 0.50))
        // Exactly the limit: a gap of `maxStep` is already an edge.
        #expect(!DepthGrouping.isSameSurface(0, DepthGrouping.maxStep))
    }

    @Test("Case D13: an unsure pixel doesn't spread the paint, and joins the nearer group it touches")
    func unsurePixelJoinsTheNearerGroup() {
        // Sure, unsure, sure: 3 cm steps would make one group if the unsure pixel spread the paint.
        let groups = DepthGrouping.groups(in: full(3, 1), depth: frame(3, 1, [1.50, 1.53, 1.56], confidence: [2, 1, 2]))
        #expect(groups.map(\.pixels) == [[1, 1, 0], [0, 0, 1]])
    }

    @Test("Case D13: a mask with only unsure pixels stays unchanged")
    func onlyUnsurePixelsStayUnchanged() {
        let groups = DepthGrouping.groups(in: full(3, 1), depth: frame(3, 1, [1.5, 2.0, 2.5], confidence: [0, 1, 0]))
        #expect(groups == [full(3, 1)])
    }

    @Test("Case D14: a split-off piece under 5% of the mask is dropped")
    func tinyPieceIsDropped() {
        var depths = [Float](repeating: 1.50, count: 40)
        depths[39] = 3.00
        var kept = [UInt8](repeating: 1, count: 40)
        kept[39] = 0
        #expect(DepthGrouping.groups(in: full(40, 1), depth: frame(40, 1, depths)).map(\.pixels) == [kept])
    }

    @Test("Case D15: the nearest group of a light at 2 m with a wall at 3 m is only the light")
    func nearestGroupIsTheLight() {
        let trimmed = DepthGrouping.nearestGroup(in: full(4, 1), depth: frame(4, 1, [2, 2, 3, 3]))
        #expect(trimmed.pixels == [1, 1, 0, 0])
    }

    @Test("Case D19: a blob that is 15% camera and 85% person gives points at the camera's distance")
    func pointsSitOnTheCamera() {
        // 20 x 3: columns 0...2 are the camera at 1.5 m (9 pixels, 15%), the rest is the person at 2 m.
        let depths = (0..<60).map { $0 % 20 < 3 ? Float(1.5) : Float(2.0) }
        let depth = frame(20, 3, depths)
        let blob = DepthSampler.worldPoints(in: full(20, 3), depth: depth, camera: makeCamera(), erosion: 0)
        #expect(blob.count == 51)   // today: the 15 cm rule lands on the person

        let camera = DepthGrouping.nearestGroup(in: full(20, 3), depth: depth)
        let points = DepthSampler.worldPoints(in: camera, depth: depth, camera: makeCamera(), erosion: 0)
        #expect(points.count == 9)
        #expect(points.allSatisfy { near($0.z, -1.5) })
    }
}
