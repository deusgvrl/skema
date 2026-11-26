//
//  PDFDiagramView.swift
//  Skema Photo
//
//  The lighting diagram as printed in the PDF: black icons around the red subject on white, with names and
//  distances. Not interactive; the app's own diagram is `LightingDiagramView`. Where everything goes is
//  `PDFDiagramLayout` (26 Nov): the drawing fills the box, a far item gets a break mark, names avoid each other.
//

import SwiftUI

struct PDFDiagramView: View {
    let nodes: [Equipment]
    var subjectRotationAngle: Double = 0.0

    private static let iconSize: CGFloat = 60
    private static let subjectDiameter: CGFloat = 52
    private static let iconRadius: CGFloat = 26

    private var arrowWidth: CGFloat { Self.subjectDiameter * 0.20 }
    private var arrowHeight: CGFloat { Self.subjectDiameter * 0.11 }
    private var arrowCenterOffset: CGFloat { Self.subjectDiameter * 0.39 }

    var body: some View {
        GeometryReader { geometry in
            let layout = PDFDiagramLayout.make(positions: nodes.map(\.position),
                                               names: nodes.map(\.labelName), in: geometry.size)
            ZStack {
                Color.white

                guides(layout)

                subject.position(layout.subject)

                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    icon(of: node).position(layout.points[index])
                }

                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    label(of: node, at: layout.points[index], side: layout.nameSides[index])
                }

                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    distanceLabel(for: node, at: layout.points[index], from: layout.subject)
                }
            }
            .overlay(alignment: .bottomTrailing) { scaleBar(scale: layout.scale).padding(12) }
        }
        .foregroundStyle(.black)
        .clipped()
    }

    /// A dashed line from the subject to each item, stopping at its icon. A line drawn shorter than it is gets two
    /// slanted ticks across it, as on technical drawings.
    private func guides(_ layout: PDFDiagramLayout.Result) -> some View {
        Path { path in
            for (index, point) in layout.points.enumerated() {
                let posX = point.x - layout.subject.x
                let posY = point.y - layout.subject.y
                let length = hypot(posX, posY)
                guard length > Self.iconRadius else { continue }
                let share = (length - Self.iconRadius) / length
                path.move(to: layout.subject)
                path.addLine(to: CGPoint(x: layout.subject.x + posX * share, y: layout.subject.y + posY * share))
                if layout.isBroken[index] {
                    addBreakMark(to: &path, from: layout.subject, along: CGPoint(x: posX, y: posY))
                }
            }
        }
        .stroke(Color(white: 0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    private func addBreakMark(to path: inout Path, from start: CGPoint, along vector: CGPoint) {
        let length = hypot(vector.x, vector.y)
        let unit = CGPoint(x: vector.x / length, y: vector.y / length)
        let normal = CGPoint(x: -unit.y, y: unit.x)
        for share in [0.72, 0.76] as [CGFloat] {
            let mid = CGPoint(x: start.x + vector.x * share, y: start.y + vector.y * share)
            path.move(to: CGPoint(x: mid.x + normal.x * 7 - unit.x * 3, y: mid.y + normal.y * 7 - unit.y * 3))
            path.addLine(to: CGPoint(x: mid.x - normal.x * 7 + unit.x * 3, y: mid.y - normal.y * 7 + unit.y * 3))
        }
    }

    private var subject: some View {
        ZStack {
            Circle()
                .fill(DesignTokens.accentPrimary)
                .frame(width: Self.subjectDiameter, height: Self.subjectDiameter)

            ZStack {
                DownTriangle()
                    .fill(Color.white)
                    .frame(width: arrowWidth, height: arrowHeight)
                    .offset(y: arrowCenterOffset)
            }
            .frame(width: Self.subjectDiameter, height: Self.subjectDiameter)
            .rotationEffect(.degrees(subjectRotationAngle))

            Text("Subject")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: Self.subjectDiameter * 0.65)
        }
        .frame(width: Self.subjectDiameter, height: Self.subjectDiameter)
    }

    private func icon(of node: Equipment) -> some View {
        Image(node.pdfImageName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: Self.iconSize, height: Self.iconSize)
            .rotationEffect(.degrees(node.rotationAngle))
    }

    // MARK: - Equipment Name

    private func label(of node: Equipment, at point: CGPoint, side: PDFDiagramLayout.NameSide) -> some View {
        let rect = PDFDiagramLayout.nameRect(for: node.labelName, at: point, side: side)
        return Text(node.labelName)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 3)
            .background(.white.opacity(0.85))
            .fixedSize()
            .position(x: rect.midX, y: rect.midY)
    }

    // MARK: - Inline Rotated Distance Label

    @ViewBuilder
    private func distanceLabel(for node: Equipment, at point: CGPoint, from centre: CGPoint) -> some View {
        let posX = point.x - centre.x
        let posY = point.y - centre.y

        if posX != 0 || posY != 0,
           let labelPos = calculateDistanceLabelPosition(posX: posX, posY: posY, centre: centre) {
            let metres = hypot(node.position.x, node.position.y) / Equipment.pointsPerMeter
            let text = node.distance.isEmpty ? String(format: "%.2f", metres) : node.distance

            let angle: Double = {
                var rawAngle = atan2(posY, posX) * 180 / .pi
                if rawAngle > 90 {
                    rawAngle -= 180
                } else if rawAngle < -90 {
                    rawAngle += 180
                }
                return rawAngle
            }()

            Text("\(text) m")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.85))
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.gray.opacity(0.4), lineWidth: 0.5)
                )
                .fixedSize()
                .rotationEffect(.degrees(angle))
                .position(labelPos)
        }
    }

    private func calculateDistanceLabelPosition(posX: CGFloat, posY: CGFloat, centre: CGPoint) -> CGPoint? {
        let length = hypot(posX, posY)
        guard length > 5 else { return nil }

        let unitX = posX / length
        let unitY = posY / length

        let minSubjectClearance: CGFloat = (Self.subjectDiameter / 2) + 14
        let minEquipmentClearance: CGFloat = 32

        let startDist = minSubjectClearance
        let endDist = max(startDist + 10, length - minEquipmentClearance)
        let midDistance = (startDist + endDist) / 2

        return CGPoint(
            x: centre.x + unitX * midDistance,
            y: centre.y + unitY * midDistance
        )
    }

    // MARK: - Dynamic Scale Bar

    private func scaleBar(scale: CGFloat) -> some View {
        let pointsPerMeterAtScale = Equipment.pointsPerMeter * scale
        let candidates: [(distance: Double, label: String)] = [
            (0.05, "0.05 m"),
            (0.1, "0.1 m"),
            (0.15, "0.15 m"),
            (0.2, "0.2 m"),
            (0.25, "0.25 m"),
            (0.5, "0.5 m"),
            (1.0, "1 m"),
            (2.0, "2 m"),
            (5.0, "5 m"),
            (10.0, "10 m")
        ]

        let targetWidth: CGFloat = 70.0

        let best = candidates.min(by: {
            abs(CGFloat($0.distance) * pointsPerMeterAtScale - targetWidth) <
            abs(CGFloat($1.distance) * pointsPerMeterAtScale - targetWidth)
        }) ?? (1.0, "1 m")

        let width = CGFloat(best.distance) * pointsPerMeterAtScale

        return VStack(spacing: 2) {
            Text(best.label).font(.system(size: 10))
            Rectangle().frame(width: width, height: 1.5)
        }
    }
}

#Preview {
    PDFDiagramView(
        nodes: [
            Equipment(
                category: .camera,
                name: "Nikon",
                position: CGPoint(x: 0, y: 24),
                lens: "30mm",
                iso: "100",
                aperture: "F2.8"
            ),
            Equipment(
                category: .light,
                name: "W200",
                position: CGPoint(x: 25, y: -20),
                power: "1/120"
            )
        ],
        subjectRotationAngle: 45.0
    )
    .frame(width: 507, height: 524)
}

private extension Equipment {
    /// The name printed by the item; Name is required, so "Equipment" is only a fallback.
    var labelName: String { name.isEmpty ? "Equipment" : name }
}

/// Where the PDF diagram draws the subject, each item and its name inside the PDF's box (26 Nov).
/// - The usual items, with the subject, fill the box (less `padding` for icons and names), wherever they sit
///   around the subject.
/// - An item more than `farFactor` times the median distance away is drawn `farGap` beyond the others, in its own
///   direction, and marked as broken (its line gets a break mark; its label keeps the real distance).
/// - Each name goes below its icon unless that would touch another icon, the subject or a name; then above, right
///   or left, whichever is free first.
enum PDFDiagramLayout {
    enum NameSide: Equatable { case below, above, right, left }

    struct Result {
        /// Diagram points per position point, for the scale bar.
        let scale: CGFloat
        /// The subject's centre in the box.
        let subject: CGPoint
        /// Each item's centre in the box, in the order given.
        let points: [CGPoint]
        /// Drawn closer than it really is.
        let isBroken: [Bool]
        let nameSides: [NameSide]
    }

    /// Room kept at the box's edges for an icon and its name.
    static let padding: CGFloat = 70
    static let farFactor: CGFloat = 2.5
    static let farGap: CGFloat = 70
    /// Never blow a tiny setup up more than this.
    static let maxScale: CGFloat = 5

    private static let iconHalf: CGFloat = 25
    private static let subjectHalf: CGFloat = 26
    private static let nameGap: CGFloat = 28
    private static let nameHeight: CGFloat = 15

    /// - Parameter positions: each item's position relative to the subject, in diagram points (100 per metre).
    static func make(positions: [CGPoint], names: [String], in box: CGSize) -> Result {
        let lengths = positions.map { hypot($0.x, $0.y) }
        let sorted = lengths.filter { $0 > 0 }.sorted()
        let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        let isFar = lengths.map { median > 0 && $0 > farFactor * median }
        let usual = [CGPoint.zero] + positions.indices.filter { !isFar[$0] }.map { positions[$0] }
        var scale = min(maxScale,
                        (box.width - 2 * padding) / max(span(usual.map(\.x)), 1),
                        (box.height - 2 * padding) / max(span(usual.map(\.y)), 1))
        let fits = { (scale: CGFloat) -> Bool in
            let all = [CGPoint.zero] + drawnOffsets(positions, lengths: lengths, isFar: isFar, scale: scale)
            return span(all.map(\.x)) + 2 * padding <= box.width + 0.01
                && span(all.map(\.y)) + 2 * padding <= box.height + 0.01
        }
        // A far item can push the drawing past the box: find the biggest scale that still fits.
        if !fits(scale) {
            var low: CGFloat = 0
            var high = scale
            for _ in 0..<40 {
                let mid = (low + high) / 2
                if fits(mid) { low = mid } else { high = mid }
            }
            scale = low
        }
        let offsets = drawnOffsets(positions, lengths: lengths, isFar: isFar, scale: scale)
        let all = [CGPoint.zero] + offsets
        let subject = CGPoint(x: box.width / 2 - middle(all.map(\.x)), y: box.height / 2 - middle(all.map(\.y)))
        let points = offsets.map { CGPoint(x: subject.x + $0.x, y: subject.y + $0.y) }
        return Result(scale: scale, subject: subject, points: points, isBroken: isFar,
                      nameSides: nameSides(points: points, names: names, subject: subject))
    }

    /// Below first; otherwise the first side that touches no other icon, the subject or a name placed before it.
    static func nameSides(points: [CGPoint], names: [String], subject: CGPoint) -> [NameSide] {
        let icons = points.map { point in
            CGRect(x: point.x - iconHalf, y: point.y - iconHalf, width: 2 * iconHalf, height: 2 * iconHalf)
        }
        let subjectRect = CGRect(x: subject.x - subjectHalf, y: subject.y - subjectHalf,
                                 width: 2 * subjectHalf, height: 2 * subjectHalf)
        var placed: [CGRect] = []
        return points.indices.map { index in
            let obstacles = icons.indices.filter { $0 != index }.map { icons[$0] } + [subjectRect] + placed
            let side = [NameSide.below, .above, .right, .left].first { side in
                let rect = nameRect(for: names[index], at: points[index], side: side)
                return !obstacles.contains { $0.intersects(rect) }
            } ?? .below
            placed.append(nameRect(for: names[index], at: points[index], side: side))
            return side
        }
    }

    /// Where a name goes on a side of its icon, from an estimate of its size at 11 pt semibold.
    static func nameRect(for name: String, at point: CGPoint, side: NameSide) -> CGRect {
        let width = CGFloat(name.count) * 6.5 + 6
        switch side {
        case .below: return CGRect(x: point.x - width / 2, y: point.y + nameGap, width: width, height: nameHeight)
        case .above:
            return CGRect(x: point.x - width / 2, y: point.y - nameGap - nameHeight, width: width, height: nameHeight)
        case .right:
            return CGRect(x: point.x + iconHalf + 7, y: point.y - nameHeight / 2, width: width, height: nameHeight)
        case .left:
            return CGRect(x: point.x - iconHalf - 7 - width, y: point.y - nameHeight / 2,
                          width: width, height: nameHeight)
        }
    }

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

    private static func span(_ values: [CGFloat]) -> CGFloat { (values.max() ?? 0) - (values.min() ?? 0) }
    private static func middle(_ values: [CGFloat]) -> CGFloat { ((values.max() ?? 0) + (values.min() ?? 0)) / 2 }
}
