//
//  PDFDiagramView.swift
//  Skema Photo
//
//  The lighting diagram as printed in the PDF: black icons around the red subject on white, with names, roles and
//  distances. Not interactive; the app's own diagram is `LightingDiagramView`.
//

import SwiftUI

struct PDFDiagramView: View {
    let nodes: [Equipment]
    var subjectRotationAngle: Double = 0.0

    private static let iconSize: CGFloat = 60
    private static let subjectDiameter: CGFloat = 52
    private static let iconRadius: CGFloat = 26
    private static let labelOffset: CGFloat = 28

    private var arrowWidth: CGFloat { Self.subjectDiameter * 0.20 }
    private var arrowHeight: CGFloat { Self.subjectDiameter * 0.11 }
    private var arrowCenterOffset: CGFloat { Self.subjectDiameter * 0.39 }

    /// Calculates scale factor:
    /// - Scales DOWN (below 1.0, down to 0.05x) for far equipment (> 15m) so canvas bounds never clip.
    /// - Scales UP (above 1.0, up to 4.5x) for tight setups (< 50cm) to expand close clusters and prevent icon overlaps.
    /// Icons, labels, and text remain at 100% fixed printable size in both cases.
    var autoScale: CGFloat {
        let activeNodes = nodes.filter { $0.position != .zero }
        guard !activeNodes.isEmpty else { return 1.0 }

        let distances = activeNodes.map { hypot($0.position.x, $0.position.y) }
        let maxDistance = distances.max() ?? 100.0
        let minDistance = distances.min() ?? 100.0

        // Target canvas radius (leaving margin for 60pt icons and labels around PDF edges)
        let maxCanvasRadius: CGFloat = 190.0
        
        // Scale required so furthest equipment fits inside standard PDF box
        let fitScale = maxCanvasRadius / max(maxDistance, 50.0)

        // Scale required so close equipment stays clear of the Subject circle
        let targetSubjectClearance: CGFloat = 95.0
        let clearanceScale = targetSubjectClearance / max(minDistance, 15.0)

        if maxDistance > maxCanvasRadius {
            // Far equipment present (e.g. > 15m / 1500pt): scale DOWN positions to fit on page (down to 0.05x)
            return max(0.05, min(1.0, fitScale))
        } else {
            // Close equipment (< 50cm): scale UP positions up to 4.5x so tight clusters clear each other
            return max(1.0, min(5.0, clearanceScale))
        }
    }

    var body: some View {
        let scale = autoScale

        GeometryReader { geometry in
            let centre = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                Color.white

                // 1. Guide Lines
                guides(from: centre, scale: scale)

                // 2. Subject Circle
                subject.position(centre)

                // 3. Equipment Icons
                ForEach(nodes) { node in
                    icon(of: node).position(scaledPoint(of: node, from: centre, scale: scale))
                }

                // 4. Equipment Name & Technical Details Labels
                ForEach(nodes) { node in
                    label(of: node, at: scaledPoint(of: node, from: centre, scale: scale))
                }

                // 5. Distance Labels (Aligned parallel along vector line)
                ForEach(nodes) { node in
                    distanceLabel(for: node, from: centre, scale: scale)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) { scaleBar(scale: scale).padding(12) }
        .foregroundStyle(.black)
        .clipped()
    }

    private func scaledPoint(of node: Equipment, from centre: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: centre.x + node.position.x * scale, y: centre.y + node.position.y * scale)
    }

    private func guides(from centre: CGPoint, scale: CGFloat) -> some View {
        Path { path in
            for node in nodes {
                let posX = node.position.x * scale
                let posY = node.position.y * scale
                let length = hypot(posX, posY)
                guard length > Self.iconRadius else { continue }
                let share = (length - Self.iconRadius) / length
                path.move(to: centre)
                path.addLine(to: CGPoint(x: centre.x + posX * share,
                                         y: centre.y + posY * share))
            }
        }
        .stroke(Color(white: 0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
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
        Image(node.category.pdfImageName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: Self.iconSize, height: Self.iconSize)
            .rotationEffect(.degrees(node.rotationAngle))
    }

    // MARK: - Equipment Label & Technical Subdetails

    private func label(of node: Equipment, at point: CGPoint) -> some View {
        VStack(spacing: 1) {
            Text(node.name.isEmpty ? "Equipment" : node.name)
                .font(.system(size: 11, weight: .semibold))

            categoryDetailsView(for: node)
        }
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .padding(.horizontal, 3)
        .background(.white.opacity(0.85))
        .frame(maxWidth: 2 * DiagramCanvas.itemPadding)
        .fixedSize(horizontal: false, vertical: true)
        .frame(height: 0, alignment: .top)
        .position(x: point.x, y: point.y + Self.labelOffset)
    }

    @ViewBuilder
    private func categoryDetailsView(for node: Equipment) -> some View {
        switch node.category {
        case .camera:
            let hasLens = !node.lens.trimmingCharacters(in: .whitespaces).isEmpty
            let hasAperture = !node.aperture.trimmingCharacters(in: .whitespaces).isEmpty
            let hasIso = !node.iso.trimmingCharacters(in: .whitespaces).isEmpty

            if hasLens || hasAperture || hasIso {
                HStack(spacing: 3) {
                    if hasLens {
                        Text(node.lens.lowercased().contains("mm") ? node.lens : "\(node.lens)mm")
                    }
                    if hasAperture {
                        if hasLens {
                            Text("•").foregroundStyle(Color.gray)
                        }
                        Text(node.aperture)
                    }
                    if hasIso {
                        if hasLens || hasAperture {
                            Text("•").foregroundStyle(Color.gray)
                        }
                        Text(node.iso.lowercased().contains("iso") ? node.iso : "ISO \(node.iso)")
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(Color.black.opacity(0.75))
            } else if !node.role.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(node.role)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.black.opacity(0.75))
            }

        case .light:
            if !node.power.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(node.power)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.black.opacity(0.75))
            } else if !node.role.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(node.role)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.black.opacity(0.75))
            }

        case .accessory:
            if !node.role.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(node.role)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.black.opacity(0.75))
            }
        }
    }

    // MARK: - Inline Rotated Distance Label

    @ViewBuilder
    private func distanceLabel(for node: Equipment, from centre: CGPoint, scale: CGFloat) -> some View {
        let posX = node.position.x * scale
        let posY = node.position.y * scale

        if (posX != 0 || posY != 0), let labelPos = calculateDistanceLabelPosition(posX: posX, posY: posY, centre: centre) {
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
                position: CGPoint(x: 0, y: 24), lens: "30mm",
                iso: "100",
                aperture: "F2.8"
            ),
            Equipment(
                category: .light,
                name: "W200",
                position: CGPoint(x: 25, y: -20), power: "1/120"
            )
        ],
        subjectRotationAngle: 45.0
    )
    .frame(width: 507, height: 524)
}
