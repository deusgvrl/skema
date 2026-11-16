/// Groups a mask's pixels by depth continuity, the "paint bucket" (A10-90, cases D10–D14).
/// Neighbouring depth pixels belong to one group while their depths change only a little; a bigger step is an edge.
public enum DepthGrouping {
    /// A depth step of this much or more between neighbours is an edge (Amadeus, 16 Nov: 5 cm).
    public static let maxStep: Float = 0.05
    /// A group smaller than this share of the mask is noise and is dropped (Amadeus, 16 Nov: 5%).
    public static let minGroupFraction: Float = 0.05
    /// Only depth pixels LiDAR is sure about spread the paint.
    public static let minConfidence: UInt8 = 2

    /// Case D12: do two neighbouring depths (metres) belong to the same surface?
    public static func isSameSurface(_ first: Float, _ second: Float) -> Bool {
        return abs(first - second) < maxStep
    }

    /// The mask split into its depth groups, nearest first. Each group is a mask of the same size.
    /// Works on the depth grid: a depth pixel counts when any mask pixel over it is 1.
    /// `[mask]` when it can't be grouped: sizes that don't fit, no sure depth pixel, or only noise-sized groups.
    public static func groups(in mask: InstanceMask, depth: DepthFrame) -> [InstanceMask] {
        let count = depth.width * depth.height
        guard depth.width > 0, depth.height > 0, mask.width > 0, mask.height > 0,
              mask.pixels.count == mask.width * mask.height,
              depth.depth.count == count, depth.confidence.count == count else { return [mask] }

        // Which depth pixel sits under each mask column and row.
        let columns = (0..<mask.width).map { min(depth.width - 1, Int((Float($0) + 0.5) / Float(mask.width) * Float(depth.width))) }
        let rows = (0..<mask.height).map { min(depth.height - 1, Int((Float($0) + 0.5) / Float(mask.height) * Float(depth.height))) }
        var covered = [Bool](repeating: false, count: count)
        for y in 0..<mask.height {
            for x in 0..<mask.width where mask.pixels[y * mask.width + x] != 0 {
                covered[rows[y] * depth.width + columns[x]] = true
            }
        }
        let sure = (0..<count).map { index in
            covered[index] && depth.confidence[index] >= minConfidence && depth.depth[index].isFinite && depth.depth[index] > 0
        }
        let seeds = (0..<count).filter { sure[$0] }.sorted { depth.depth[$0] < depth.depth[$1] }
        guard !seeds.isEmpty else { return [mask] }

        // Paint from the nearest unpainted sure pixel, so groups come out nearest first.
        var label = [Int](repeating: -1, count: count)
        var groupCount = 0
        for seed in seeds where label[seed] < 0 {
            label[seed] = groupCount
            var stack = [seed]
            while let current = stack.popLast() {
                for next in neighbours(of: current, width: depth.width, height: depth.height)
                where sure[next] && label[next] < 0 && isSameSurface(depth.depth[current], depth.depth[next]) {
                    label[next] = groupCount
                    stack.append(next)
                }
            }
            groupCount += 1
        }

        // Unsure pixels join the group they touch. Nearer groups go first, so they win a tie (case D13).
        var queue = (0..<count).filter { label[$0] >= 0 }.sorted { label[$0] < label[$1] }
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            for next in neighbours(of: current, width: depth.width, height: depth.height)
            where covered[next] && !sure[next] && label[next] < 0 {
                label[next] = label[current]
                queue.append(next)
            }
        }

        // Drop noise-sized groups (case D14).
        var sizes = [Int](repeating: 0, count: groupCount)
        for index in 0..<count where label[index] >= 0 { sizes[label[index]] += 1 }
        let total = covered.count(where: { $0 })
        let kept = (0..<groupCount).filter { Float(sizes[$0]) >= minGroupFraction * Float(total) }
        guard !kept.isEmpty else { return [mask] }

        return kept.map { group in
            var pixels = [UInt8](repeating: 0, count: mask.pixels.count)
            for y in 0..<mask.height {
                for x in 0..<mask.width where mask.pixels[y * mask.width + x] != 0
                    && label[rows[y] * depth.width + columns[x]] == group {
                    pixels[y * mask.width + x] = 1
                }
            }
            return InstanceMask(width: mask.width, height: mask.height, pixels: pixels)
        }
    }

    /// The mask cut down to its nearest group. The mask itself when it can't be grouped.
    public static func nearestGroup(in mask: InstanceMask, depth: DepthFrame) -> InstanceMask {
        groups(in: mask, depth: depth).first ?? mask
    }

    /// The up, down, left and right neighbours of a depth pixel that are inside the grid.
    private static func neighbours(of index: Int, width: Int, height: Int) -> [Int] {
        let x = index % width, y = index / width
        var result: [Int] = []
        if x > 0 { result.append(index - 1) }
        if x < width - 1 { result.append(index + 1) }
        if y > 0 { result.append(index - width) }
        if y < height - 1 { result.append(index + width) }
        return result
    }
}
