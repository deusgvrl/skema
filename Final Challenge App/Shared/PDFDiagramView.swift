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

    private static let iconSize: CGFloat = 80
    private static let subjectDiameter: CGFloat = 64
    /// How far from an item's centre its icon reaches; the guide stops there, as the icons are see-through.
    private static let iconRadius: CGFloat = 34
    private static let labelOffset: CGFloat = 36

    var body: some View {
        GeometryReader { geometry in
            let centre = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                Color.white
                guides(from: centre)
                subject.position(centre)
                ForEach(nodes) { node in
                    icon(of: node).position(point(of: node, from: centre))
                }
                ForEach(nodes) { node in
                    label(of: node, at: point(of: node, from: centre))
                }
                // Last, so a name never hides a distance.
                ForEach(nodes) { node in
                    distance(of: node, from: centre)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) { scaleBar.padding(12) }
        .foregroundStyle(.black)
        .clipped()
    }

    private func point(of node: Equipment, from centre: CGPoint) -> CGPoint {
        CGPoint(x: centre.x + node.position.x, y: centre.y + node.position.y)
    }

    private func guides(from centre: CGPoint) -> some View {
        Path { path in
            for node in nodes {
                let length = hypot(node.position.x, node.position.y)
                guard length > Self.iconRadius else { continue }
                let share = (length - Self.iconRadius) / length
                path.move(to: centre)
                path.addLine(to: CGPoint(x: centre.x + node.position.x * share,
                                         y: centre.y + node.position.y * share))
            }
        }
        .stroke(Color(white: 0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    private var subject: some View {
        Circle()
            .fill(DesignTokens.accentPrimary)
            .frame(width: Self.subjectDiameter, height: Self.subjectDiameter)
            .overlay {
                Text("Subject")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
    }

    private func icon(of node: Equipment) -> some View {
        Image(node.category.pdfImageName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: Self.iconSize, height: Self.iconSize)
            .rotationEffect(.degrees(node.rotationAngle))
    }

    /// The name, and the role under it. Never wider than the room `DiagramCanvas` keeps around an item.
    private func label(of node: Equipment, at point: CGPoint) -> some View {
        let role = node.role.trimmingCharacters(in: .whitespaces)
        return VStack(spacing: 0) {
            Text(node.name.isEmpty ? "Equipment" : node.name)
                .font(.system(size: 12, weight: .semibold))
            if !role.isEmpty {
                Text(role).font(.system(size: 11))
            }
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
    private func distance(of node: Equipment, from centre: CGPoint) -> some View {
        if node.position != .zero {
            let metres = hypot(node.position.x, node.position.y) / Equipment.pointsPerMeter
            let text = node.distance.isEmpty ? String(format: "%.2f", metres) : node.distance
            Text("\(text) m")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 4)
                .background(.white)
                .fixedSize()
                .position(x: centre.x + node.position.x / 2, y: centre.y + node.position.y / 2)
        }
    }

    /// One metre at the diagram's scale. It shrinks with the diagram when that is fitted into the PDF's box.
    private var scaleBar: some View {
        VStack(spacing: 2) {
            Text("1 m").font(.system(size: 11))
            Rectangle().frame(width: Equipment.pointsPerMeter, height: 1.5)
        }
    }
}

#Preview {
    PDFDiagramView(nodes: [
        Equipment(category: .camera, name: "Sony A7 IV", role: "Main", position: CGPoint(x: 0, y: 180)),
        Equipment(category: .light, name: "Profoto D2", role: "Key", position: CGPoint(x: -150, y: -100))
    ])
    .frame(width: 507, height: 524)
}
