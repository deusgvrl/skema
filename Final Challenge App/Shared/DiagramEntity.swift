//
//  DiagramEntity.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 17/11/26.
//
//  The subject on the diagram: a card with a figure and its title (Sketch R04 "Set / Table").
//

import SwiftUI

struct DiagramEntity: View {
    let title: String
    /// Kept to preserve backward compatibility with existing call sites
    var icon: String = ""
    let position: CGPoint
    var currentScale: CGFloat = 1.0
    var isSelected: Bool = false
    var isReadOnly: Bool = false
    @Binding var rotationAngle: Double
    var onTap: () -> Void
    var onGestureStart: () -> Void
    var onGestureEnd: () -> Void

    init(
        title: String,
        icon: String = "",
        position: CGPoint,
        currentScale: CGFloat = 1.0,
        isSelected: Bool = false,
        isReadOnly: Bool = false,
        rotationAngle: Binding<Double> = .constant(0),
        onTap: @escaping () -> Void,
        onGestureStart: @escaping () -> Void = {},
        onGestureEnd: @escaping () -> Void = {}
    ) {
        self.title = title
        self.icon = icon
        self.position = position
        self.currentScale = currentScale
        self.isSelected = isSelected
        self.isReadOnly = isReadOnly
        self._rotationAngle = rotationAngle
        self.onTap = onTap
        self.onGestureStart = onGestureStart
        self.onGestureEnd = onGestureEnd
    }

    @ScaledMetric(relativeTo: .caption) private var circleDimension: CGFloat = 64

    // Rotation state (mirrors NodeView)
    @State private var isRotating = false
    @State private var globalCenter: CGPoint = .zero
    @State private var stretchedDistance: CGFloat?
    @State private var grabOffset: CGFloat = 0
    @State private var snapFeedback: UIImpactFeedbackGenerator?
    @State private var lastRotationSnap: Int?

    private var effectiveSize: CGFloat {
        min(max(circleDimension, 64), 84)
    }

    // Arrow proportions tuned to sit cleanly near outer perimeter without encroaching on center
    private var arrowWidth: CGFloat { effectiveSize * 0.20 }
    private var arrowHeight: CGFloat { effectiveSize * 0.11 }
    private var arrowCenterOffset: CGFloat { effectiveSize * 0.40 }

    private var defaultHandleDistance: CGFloat { effectiveSize / 2 + 38 }
    private var handleDistance: CGFloat { stretchedDistance ?? defaultHandleDistance }

    var body: some View {
        ZStack {
            // Circle + arrow + title: this is the only tappable area for onTap
            ZStack {
                Circle()
                    .fill(DesignTokens.accentPrimary)
                    .frame(width: effectiveSize, height: effectiveSize)

                // White direction arrow (rotates with the subject)
                ZStack {
                    DownTriangle()
                        .fill(Color.white)
                        .frame(width: arrowWidth, height: arrowHeight)
                        .offset(y: arrowCenterOffset)
                }
                .frame(width: effectiveSize, height: effectiveSize)
                .rotationEffect(.degrees(rotationAngle))

                // Title text (stays upright, constrained to safe inner radius)
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(maxWidth: effectiveSize * 0.60)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
            .contentShape(Circle())
            .onTapGesture { if !isRotating { onTap() } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityHint("Shows the subject’s details.")
            .accessibilityAddTraits(.isButton)

            // Rotation handle layer (outside the circle)
            if isSelected && !isReadOnly {
                let lineLength = max(10, handleDistance - effectiveSize / 2 - 14)

                ZStack {
                    DashedLine()
                        .stroke(DesignTokens.accentPrimary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 2, height: lineLength)
                        .offset(y: effectiveSize / 2 + lineLength / 2)
                        .shadow(color: DesignTokens.accentPrimary.opacity(0.3), radius: 2)
                        .allowsHitTesting(false)

                    Image(systemName: "arrow.trianglehead.clockwise.rotate.90")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(DesignTokens.accentPrimary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(DesignTokens.diagramNodeFill)
                                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                        )
                        .overlay(Circle().stroke(DesignTokens.accentPrimary, lineWidth: 1.5))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .offset(y: handleDistance)
                        .transition(.scale.combined(with: .opacity))
                        .highPriorityGesture(rotationGesture)
                }
                .rotationEffect(.degrees(rotationAngle))
            }
        }
        .frame(width: effectiveSize, height: effectiveSize)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { updateGlobalCenter(geo) }
                    .onChange(of: geo.frame(in: .global)) { _, _ in updateGlobalCenter(geo) }
            }
        )
        .onChange(of: isSelected) { _, selected in
            if !selected {
                isRotating = false
                stretchedDistance = nil
            }
        }
        .scaleEffect(1 / currentScale)
        .position(position)
    }

    // MARK: - Rotation

    private var rotationGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let deltaX = value.location.x - globalCenter.x
                let deltaY = value.location.y - globalCenter.y
                let fingerDistance = hypot(deltaX, deltaY)

                if !isRotating {
                    isRotating = true
                    onGestureStart()
                    grabOffset = fingerDistance - handleDistance
                    snapFeedback = UIImpactFeedbackGenerator(style: .medium)
                    snapFeedback?.prepare()
                }

                stretchedDistance = max(defaultHandleDistance, fingerDistance - grabOffset)

                // 0° = pointing down (6 o'clock), matching the default arrow position
                var visualAngle = (atan2(deltaY, deltaX) * 180 / .pi) - 90
                if visualAngle < 0 { visualAngle += 360 }

                rotationAngle = applyRotationSnap(to: visualAngle)
            }
            .onEnded { _ in
                guard isRotating else { return }
                isRotating = false
                lastRotationSnap = nil
                grabOffset = 0
                snapFeedback = nil
                onGestureEnd()

                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    stretchedDistance = nil
                }
            }
    }

    private func updateGlobalCenter(_ geo: GeometryProxy) {
        let frame = geo.frame(in: .global)
        globalCenter = CGPoint(x: frame.midX, y: frame.midY)
    }

    private func applyRotationSnap(to rawAngle: Double) -> Double {
        let snapAngles = [0, 45, 90, 135, 180, 225, 270, 315]
        let tolerance: Double = 3.5

        for target in snapAngles {
            let diff = abs(rawAngle - Double(target))
            if min(diff, 360.0 - diff) <= tolerance {
                if lastRotationSnap != target {
                    lastRotationSnap = target
                    snapFeedback?.impactOccurred()
                    snapFeedback?.prepare()
                }
                return Double(target)
            }
        }
        lastRotationSnap = nil
        return rawAngle
    }
}

// MARK: - Arrow shape (triangle pointing down)

struct DownTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    struct Wrapper: View {
        @State var angle = 90.0
        var body: some View {
            ZStack {
                DesignTokens.pageBackground
                DiagramEntity(
                    title: "Subject",
                    position: CGPoint(x: 150, y: 150),
                    isSelected: true,
                    rotationAngle: $angle,
                    onTap: {}
                )
            }
            .frame(width: 300, height: 300)
        }
    }
    return Wrapper()
}
