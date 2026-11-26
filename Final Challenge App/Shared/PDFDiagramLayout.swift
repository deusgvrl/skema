//
//  PDFDiagramLayout.swift
//  Skema Photo
//
//  Where the PDF diagram draws everything, so nothing overlaps (moved out of PDFDiagramView.swift, 27 Nov).
//

import CoreGraphics

/// Where the PDF diagram draws the subject, each item, its name and its distance inside the PDF's box.
/// - The usual items, with the subject, fill the box (less `padding` for icons and names), wherever they sit
///   around the subject (26 Nov).
/// - An item more than `farFactor` times the median distance away is drawn `farGap` beyond the others, in its own
///   direction, and marked as broken (its line gets a break mark; its label keeps the real distance).
/// - Icons keep `iconGap` apart, using each icon's real drawn shape turned with the item (27 Nov).
/// - Each name goes on the side facing away from the subject first, avoiding icons, lines and other names.
/// - Each distance label slides along its line to a free spot, or sits beside a line too short for it.
enum PDFDiagramLayout {
    enum NameSide: Equatable { case below, above, right, left }

    /// One item to place.
    struct Item {
        /// Position relative to the subject, in diagram points (100 per metre).
        var position: CGPoint
        var name: String
        /// The icon's drawn size before turning (`footprint(of:accessoryType:)`).
        var footprint = CGSize(width: 50, height: 50)
        /// Degrees, as `Equipment.rotationAngle`.
        var rotation: Double = 0
        /// The distance label, such as "2.16 m"; empty for none.
        var distanceText = ""
    }

    struct Result {
        /// Diagram points per position point, for the scale bar.
        let scale: CGFloat
        /// The subject's centre in the box.
        let subject: CGPoint
        /// Each item's centre in the box, in the order given.
        let points: [CGPoint]
        /// Drawn closer than it really is.
        let isBroken: [Bool]
        /// Each icon's space in the box, turned with the item.
        let iconRects: [CGRect]
        let nameSides: [NameSide]
        let nameRects: [CGRect]
        /// The space around each distance label, or nil when the item has none.
        let distanceRects: [CGRect?]
    }

    /// Room kept at the box's edges for an icon and its name.
    static let padding: CGFloat = 70
    static let farFactor: CGFloat = 2.5
    static let farGap: CGFloat = 70
    /// Never blow a tiny setup up more than this.
    static let maxScale: CGFloat = 5
    /// Room kept between two icons, and between an icon and the subject.
    static let iconGap: CGFloat = 6
    static let subjectSize = CGSize(width: 52, height: 52)
    /// Room kept between the subject and each icon so its line can hold its distance label ("0.81 m").
    static let labelRoom: CGFloat = 48

    private static let nameHeight: CGFloat = 15
    private static let labelHeight: CGFloat = 14

    /// The shape an icon is drawn at in the PDF's 60 pt frame, measured from its PNG (27 Nov): light and camera are
    /// tall, the accessories are wide, flat bars.
    static func footprint(of category: EquipmentCategory, accessoryType: AccessoryType) -> CGSize {
        switch category {
        case .light: return CGSize(width: 26, height: 43)
        case .camera: return CGSize(width: 22, height: 38)
        case .accessory:
            switch accessoryType {
            case .reflector: return CGSize(width: 45, height: 10)
            case .diffuser: return CGSize(width: 46, height: 7)
            case .backdrop: return CGSize(width: 52, height: 21)
            }
        }
    }

    /// The upright box around `size` turned by `degrees`.
    static func rotatedSize(_ size: CGSize, degrees: Double) -> CGSize {
        let radians = degrees * .pi / 180
        let cosine = abs(CGFloat(cos(radians))), sine = abs(CGFloat(sin(radians)))
        return CGSize(width: size.width * cosine + size.height * sine, height: size.width * sine + size.height * cosine)
    }

    /// Items without shapes or distances, for callers that only need positions and names.
    static func make(positions: [CGPoint], names: [String], in box: CGSize) -> Result {
        make(items: positions.indices.map { Item(position: positions[$0], name: names[$0]) }, in: box)
    }

    static func make(items: [Item], in box: CGSize) -> Result {
        let positions = items.map(\.position)
        let lengths = positions.map { hypot($0.x, $0.y) }
        let sorted = lengths.filter { $0 > 0 }.sorted()
        let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        let isFar = lengths.map { median > 0 && $0 > farFactor * median }
        let sizes = items.map { rotatedSize($0.footprint, degrees: $0.rotation) }
        let usual = [CGPoint.zero] + positions.indices.filter { !isFar[$0] }.map { positions[$0] }

        let offsetsAt = { (scale: CGFloat) -> [CGPoint] in
            separated(drawnOffsets(positions, lengths: lengths, isFar: isFar, scale: scale), sizes: sizes)
        }
        let fits = { (offsets: [CGPoint]) -> Bool in
            let all = [CGPoint.zero] + offsets
            return span(all.map(\.x)) + 2 * padding <= box.width + 0.01
                && span(all.map(\.y)) + 2 * padding <= box.height + 0.01
        }
        var scale = min(maxScale,
                        (box.width - 2 * padding) / max(span(usual.map(\.x)), 1),
                        (box.height - 2 * padding) / max(span(usual.map(\.y)), 1))
        var offsets = offsetsAt(scale)
        // A far item, or icons pushed apart, can take the drawing past the box: find the biggest scale that fits.
        if !fits(offsets) {
            var low: CGFloat = 0
            var high = scale
            for _ in 0..<40 {
                let mid = (low + high) / 2
                if fits(offsetsAt(mid)) { low = mid } else { high = mid }
            }
            scale = low
            offsets = offsetsAt(scale)
        }

        let all = [CGPoint.zero] + offsets
        let subject = CGPoint(x: box.width / 2 - middle(all.map(\.x)), y: box.height / 2 - middle(all.map(\.y)))
        let points = offsets.map { CGPoint(x: subject.x + $0.x, y: subject.y + $0.y) }
        let iconRects = points.indices.map { rect(around: points[$0], size: sizes[$0]) }
        let subjectRect = rect(around: subject, size: subjectSize)
        let scene = Scene(points: points, sizes: sizes, iconRects: iconRects, subject: subject,
                          subjectRect: subjectRect, bounds: CGRect(origin: .zero, size: box))
        let names = placeNames(items.map(\.name), in: scene)
        let distances = placeDistances(items.map(\.distanceText), in: scene,
                                       obstacles: iconRects + [subjectRect] + names.rects)
        return Result(scale: scale, subject: subject, points: points, isBroken: isFar, iconRects: iconRects,
                      nameSides: names.sides, nameRects: names.rects, distanceRects: distances)
    }

    /// What names and distance labels are placed around, once the icons are placed.
    private struct Scene {
        let points: [CGPoint]
        let sizes: [CGSize]
        let iconRects: [CGRect]
        let subject: CGPoint
        let subjectRect: CGRect
        let bounds: CGRect
    }

    // MARK: Icons

    private static func drawnOffsets(_ positions: [CGPoint], lengths: [CGFloat], isFar: [Bool],
                                     scale: CGFloat) -> [CGPoint] {
        let reach = positions.indices.filter { !isFar[$0] }.map { lengths[$0] * scale }.max() ?? 0
        return positions.indices.map { index in
            let position = positions[index]
            guard isFar[index] else { return CGPoint(x: position.x * scale, y: position.y * scale) }
            let drawn = reach + farGap
            return CGPoint(x: position.x / lengths[index] * drawn, y: position.y / lengths[index] * drawn)
        }
    }

    /// Pushes touching icons apart (half each) and icons off the subject (which stays), until none touch. Around the
    /// subject it keeps `labelRoom` more, so a very close item's line still has room for its distance.
    private static func separated(_ start: [CGPoint], sizes: [CGSize]) -> [CGPoint] {
        var points = start
        let keepOut = CGSize(width: subjectSize.width + 2 * labelRoom, height: subjectSize.height + 2 * labelRoom)
        for _ in 0..<30 {
            var moved = false
            for first in points.indices {
                if let push = push(points[first], sizes[first], awayFrom: .zero, keepOut) {
                    points[first] = CGPoint(x: points[first].x + push.x, y: points[first].y + push.y)
                    moved = true
                }
                for second in points.indices where second > first {
                    guard let push = push(points[first], sizes[first], awayFrom: points[second], sizes[second])
                    else { continue }
                    points[first] = CGPoint(x: points[first].x + push.x / 2, y: points[first].y + push.y / 2)
                    points[second] = CGPoint(x: points[second].x - push.x / 2, y: points[second].y - push.y / 2)
                    moved = true
                }
            }
            if !moved { break }
        }
        return points
    }

    /// How far `point` must move, straight away from `other`, so their shapes (plus `iconGap`) stop touching;
    /// nil when they don't touch.
    private static func push(_ point: CGPoint, _ size: CGSize,
                             awayFrom other: CGPoint, _ otherSize: CGSize) -> CGPoint? {
        let deltaX = point.x - other.x, deltaY = point.y - other.y
        let needX = (size.width + otherSize.width) / 2 + iconGap
        let needY = (size.height + otherSize.height) / 2 + iconGap
        guard abs(deltaX) < needX, abs(deltaY) < needY else { return nil }
        let length = hypot(deltaX, deltaY)
        // On top of each other: move straight up.
        let unit = length < 0.001 ? CGPoint(x: 0, y: -1) : CGPoint(x: deltaX / length, y: deltaY / length)
        let alongX = abs(unit.x) > 0.001 ? (needX - abs(deltaX)) / abs(unit.x) : .infinity
        let alongY = abs(unit.y) > 0.001 ? (needY - abs(deltaY)) / abs(unit.y) : .infinity
        let distance = min(alongX, alongY) + 0.01
        return CGPoint(x: unit.x * distance, y: unit.y * distance)
    }

    // MARK: Names

    /// Away from the subject first, then the other sides; the first inside the box that touches no icon, line or name.
    private static func placeNames(_ names: [String], in scene: Scene) -> (sides: [NameSide], rects: [CGRect]) {
        let points = scene.points, iconRects = scene.iconRects, subject = scene.subject, bounds = scene.bounds
        var sides: [NameSide] = []
        var rects: [CGRect] = []
        for index in points.indices {
            let obstacles = iconRects.indices.filter { $0 != index }.map { iconRects[$0] } + [scene.subjectRect] + rects
            let candidates = outwardSides(from: subject, to: points[index]).map { side in
                (side, nameRect(for: names[index], beside: iconRects[index], side: side))
            }
            let clear = { (rect: CGRect) in bounds.contains(rect) && !obstacles.contains { $0.intersects(rect) } }
            let chosen = candidates.first { candidate in
                clear(candidate.1) && !points.contains { segment(from: subject, to: $0, crosses: candidate.1) }
            } ?? candidates.first { clear($0.1) } ?? candidates[0]
            sides.append(chosen.0)
            rects.append(chosen.1)
        }
        return (sides, rects)
    }

    private static func outwardSides(from subject: CGPoint, to point: CGPoint) -> [NameSide] {
        let deltaX = point.x - subject.x, deltaY = point.y - subject.y
        let vertical: [NameSide] = deltaY < 0 ? [.above, .below] : [.below, .above]
        let horizontal: [NameSide] = deltaX < 0 ? [.left, .right] : [.right, .left]
        return abs(deltaY) >= abs(deltaX)
            ? [vertical[0], horizontal[0], horizontal[1], vertical[1]]
            : [horizontal[0], vertical[0], vertical[1], horizontal[1]]
    }

    /// Where a name goes on a side of its icon, from an estimate of its size at 11 pt semibold.
    static func nameRect(for name: String, beside icon: CGRect, side: NameSide) -> CGRect {
        let width = CGFloat(name.count) * 6.5 + 6
        switch side {
        case .below: return CGRect(x: icon.midX - width / 2, y: icon.maxY + 3, width: width, height: nameHeight)
        case .above:
            return CGRect(x: icon.midX - width / 2, y: icon.minY - 3 - nameHeight, width: width, height: nameHeight)
        case .right: return CGRect(x: icon.maxX + 4, y: icon.midY - nameHeight / 2, width: width, height: nameHeight)
        case .left:
            return CGRect(x: icon.minX - 4 - width, y: icon.midY - nameHeight / 2, width: width, height: nameHeight)
        }
    }

    // MARK: Distances

    /// Each label along the visible part of its line (halfway first), else beside the line, avoiding `obstacles`
    /// and the labels placed before it. Shorter lines go first: they have the fewest free spots.
    private static func placeDistances(_ texts: [String], in scene: Scene, obstacles: [CGRect]) -> [CGRect?] {
        let points = scene.points, subject = scene.subject
        var placed: [CGRect] = []
        var result = [CGRect?](repeating: nil, count: points.count)
        let length = { (index: Int) in hypot(points[index].x - subject.x, points[index].y - subject.y) }
        let order = points.indices.sorted { length($0) < length($1) }
        for index in order {
            result[index] = distanceRect(texts[index], of: index, in: scene, avoiding: obstacles + placed)
            if let rect = result[index] { placed.append(rect) }
        }
        return result
    }

    private static func distanceRect(_ text: String, of index: Int, in scene: Scene,
                                     avoiding obstacles: [CGRect]) -> CGRect? {
        let point = scene.points[index], iconSize = scene.sizes[index], subject = scene.subject
        let bounds = scene.bounds
        let deltaX = point.x - subject.x, deltaY = point.y - subject.y
        let length = hypot(deltaX, deltaY)
        guard !text.isEmpty, length > 5 else { return nil }
        let unit = CGPoint(x: deltaX / length, y: deltaY / length)
        let size = rotatedSize(CGSize(width: CGFloat(text.count) * 5.6 + 10, height: labelHeight),
                               degrees: Double(atan2(deltaY, deltaX)) * 180 / .pi)
        let start = subjectSize.width / 2 + 4
        let iconReach = abs(unit.x) * iconSize.width / 2 + abs(unit.y) * iconSize.height / 2
        let end = max(start, length - iconReach - 4)
        let along = [0.5, 0.4, 0.6, 0.3, 0.7, 0.2, 0.8].map { (share: CGFloat) -> CGPoint in
            let distance = start + (end - start) * share
            return CGPoint(x: subject.x + unit.x * distance, y: subject.y + unit.y * distance)
        }
        // Beside the line, close first, at each of the same spots.
        let normal = CGPoint(x: -unit.y, y: unit.x)
        let beside = [labelHeight / 2 + 8, labelHeight + 16].flatMap { offset in
            along.flatMap { spot in
                [1, -1].map { (sign: CGFloat) in
                    CGPoint(x: spot.x + normal.x * offset * sign, y: spot.y + normal.y * offset * sign)
                }
            }
        }
        let candidates = (along + beside).map { rect(around: $0, size: size) }
        return candidates.first { candidate in
            bounds.contains(candidate) && !obstacles.contains { $0.intersects(candidate) }
        } ?? candidates[0]
    }

    // MARK: Geometry

    private static func rect(around centre: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2, width: size.width, height: size.height)
    }

    /// Whether the straight line from `start` to `end` passes through `rect` (Liang–Barsky).
    static func segment(from start: CGPoint, to end: CGPoint, crosses rect: CGRect) -> Bool {
        let deltaX = end.x - start.x, deltaY = end.y - start.y
        var low: CGFloat = 0, high: CGFloat = 1
        let edges = [(-deltaX, start.x - rect.minX), (deltaX, rect.maxX - start.x),
                     (-deltaY, start.y - rect.minY), (deltaY, rect.maxY - start.y)]
        for (direction, room) in edges {
            if direction == 0 {
                if room < 0 { return false }
            } else {
                let share = room / direction
                if direction < 0 { low = max(low, share) } else { high = min(high, share) }
                if low > high { return false }
            }
        }
        return true
    }

    private static func span(_ values: [CGFloat]) -> CGFloat { (values.max() ?? 0) - (values.min() ?? 0) }
    private static func middle(_ values: [CGFloat]) -> CGFloat { ((values.max() ?? 0) + (values.min() ?? 0)) / 2 }
}
