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
            let layout = PDFDiagramLayout.make(items: nodes.map(\.layoutItem), in: geometry.size)
            ZStack {
                Color.white

                guides(layout)

                subject.position(layout.subject)

                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    icon(of: node).position(layout.points[index])
                }

                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    label(of: node, in: layout.nameRects[index])
                }

                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    distanceLabel(for: node, in: layout.distanceRects[index], at: layout.points[index],
                                  from: layout.subject)
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

    private func label(of node: Equipment, in rect: CGRect) -> some View {
        Text(node.labelName)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 3)
            .background(.white.opacity(0.85))
            .fixedSize()
            .position(x: rect.midX, y: rect.midY)
    }

    // MARK: - Inline Rotated Distance Label

    /// The distance along the line, turned to read along it, in the free spot the layout found.
    @ViewBuilder
    private func distanceLabel(for node: Equipment, in rect: CGRect?, at point: CGPoint,
                               from centre: CGPoint) -> some View {
        if let rect {
            let angle: Double = {
                var rawAngle = atan2(point.y - centre.y, point.x - centre.x) * 180 / .pi
                if rawAngle > 90 {
                    rawAngle -= 180
                } else if rawAngle < -90 {
                    rawAngle += 180
                }
                return rawAngle
            }()

            Text(node.distanceText)
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
                .position(x: rect.midX, y: rect.midY)
        }
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

    /// "2.16 m": the distance typed or scanned, else measured from the diagram.
    var distanceText: String {
        let metres = hypot(position.x, position.y) / Equipment.pointsPerMeter
        return "\(distance.isEmpty ? String(format: "%.2f", metres) : distance) m"
    }

    var layoutItem: PDFDiagramLayout.Item {
        PDFDiagramLayout.Item(position: position, name: labelName,
                              footprint: PDFDiagramLayout.footprint(of: category, accessoryType: accessoryType),
                              rotation: rotationAngle, distanceText: distanceText)
    }
}
