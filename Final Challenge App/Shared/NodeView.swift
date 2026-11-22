//
//  NodeView.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 16/11/26.
//
import SwiftUI

struct NodeView: View {
    @Binding var node: Equipment
    let subjectCenter: CGPoint
    let isSelected: Bool
    var isReadOnly: Bool = false
    var zoomScale: CGFloat = 1.0

    var onTap: () -> Void
    var onGestureStart: () -> Void
    var onGestureEnd: () -> Void

    // Rotation & Handle Stretch States
    @State private var isRotating = false
    @State private var isDragging = false
    @State private var globalCenter: CGPoint = .zero
    @State private var dragStartPosition: CGPoint = .zero

    // Dynamic Handle Distance State (Stretches on drag, snaps back on release)
    private let defaultHandleDistance: CGFloat = 72.0

    // Rotation Haptic State
    @State private var lastHapticAngle: Double = 0.0
    @State private var feedbackGenerator: UISelectionFeedbackGenerator?

    @State private var currentHandleDistance: CGFloat = 72.0
    @State private var grabOffset: CGFloat = 0   // NEW

    // Cardinal Alignment Drag Haptic State (12, 3, 6, 9 o'clock)
    @State private var lastCardinalSnap: Int?

    var body: some View {
        ZStack {
            // 1. Rotating Equipment Shape, Directional Arrow & Rotate Handle
            ZStack {
                switch node.category {
                case .camera:
                    TopViewCameraShapeView(isSelected: isSelected)

                case .light:
                    TopViewLightShapeView(isSelected: isSelected)

                case .accessory:
                    TopViewAccessoryShapeView(isSelected: isSelected)
                }

                // Directional Pointer Ray & Front Rotate Handle
                if isSelected && !isReadOnly {
                    let lineLength = max(10, currentHandleDistance - 48)

                    // Dashed Line extending forward from the node
                    DashedLine()
                        .stroke(DesignTokens.accentPrimary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 2, height: lineLength)
                        .offset(y: -(currentHandleDistance + 4) / 2)
                        .shadow(color: DesignTokens.accentPrimary.opacity(0.3), radius: 2)

                    // Directional Chevron Arrowhead (placed right below rotation handle)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DesignTokens.accentPrimary)
                        .offset(y: -currentHandleDistance + 20)
                        .shadow(color: DesignTokens.accentPrimary.opacity(0.4), radius: 2)

                    // Stretchable Rotation Handle Button (positioned at the top tip)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(DesignTokens.accentPrimary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(DesignTokens.diagramNodeFill)
                                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                        )
                        .overlay(
                            Circle()
                                .stroke(DesignTokens.accentPrimary, lineWidth: 1.5)
                        )
                        .offset(y: -currentHandleDistance)
                        .transition(.scale.combined(with: .opacity))
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                .onChanged { value in
                                    let dx = value.location.x - globalCenter.x
                                    let dy = value.location.y - globalCenter.y

                                    // Screen-space distance (node is counter-scaled, so 1 unit == 1 screen point)
                                    let fingerDistance = hypot(dx, dy)

                                    if !isRotating {
                                        isRotating = true
                                        onGestureStart()

                                        // Remember where on the handle the finger grabbed, so there's no jump
                                        grabOffset = fingerDistance - currentHandleDistance

                                        feedbackGenerator = UISelectionFeedbackGenerator()
                                        feedbackGenerator?.prepare()
                                        lastHapticAngle = node.rotationAngle
                                    }

                                    // Stretch: same feel at every zoom level
                                    currentHandleDistance = max(defaultHandleDistance, fingerDistance - grabOffset)

                                    // Angle for front-positioned handle (-Y direction)
                                    var visualAngle = (atan2(dy, dx) * 180 / .pi) + 90
                                    if visualAngle < 0 { visualAngle += 360 }

                                    let step = 3.0
                                    if Int(visualAngle / step) != Int(lastHapticAngle / step) {
                                        feedbackGenerator?.selectionChanged()
                                        feedbackGenerator?.prepare()
                                        lastHapticAngle = visualAngle
                                    }

                                    node.rotationAngle = visualAngle
                                    node.syncHorizontalAimFromRotation()
                                }
                                .onEnded { _ in
                                    guard isRotating else { return }
                                    isRotating = false
                                    grabOffset = 0
                                    onGestureEnd()
                                    feedbackGenerator = nil

                                    // Snap back only after the handle is released
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                        currentHandleDistance = defaultHandleDistance
                                    }
                                }
                        )
                }
            }
            .rotationEffect(.degrees(node.rotationAngle))
        }
        .frame(width: 44, height: 44)
        .onChange(of: isSelected) { _, selected in
            if !selected {
                isRotating = false
                currentHandleDistance = defaultHandleDistance
            }
        }
        .background {
            if node.category == .light {
                Circle()
                    .fill(RadialGradient(colors: [DesignTokens.diagramGlow, .clear], center: .center,
                                         startRadius: 0, endRadius: 55))
                    .frame(width: 110, height: 110)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        let frame = geo.frame(in: .global)
                        globalCenter = CGPoint(x: frame.midX, y: frame.midY)
                    }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                        globalCenter = CGPoint(x: newFrame.midX, y: newFrame.midY)
                    }
            }
        )
        .overlay(alignment: .bottom) {
            Text(node.displayName)
                .font(.caption)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
                .fixedSize()
                .offset(y: 20)
        }
        .scaleEffect(1 / zoomScale)
        .position(
            x: subjectCenter.x + node.position.x,
            y: subjectCenter.y + node.position.y
        )
        .highPriorityGesture(
            TapGesture().onEnded {
                if !isRotating { onTap() }
            }
        )
        .gesture(
            isReadOnly ? nil :
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    guard !isReadOnly, !isRotating else { return }

                    if !isDragging {
                        isDragging = true
                        dragStartPosition = node.position
                        onGestureStart()
                    }

                    let canvasDeltaX = value.translation.width / zoomScale
                    let canvasDeltaY = value.translation.height / zoomScale

                    let rawX = dragStartPosition.x + canvasDeltaX
                    let rawY = dragStartPosition.y + canvasDeltaY
                    let rawPosition = CGPoint(x: rawX, y: rawY)

                    let snappedPosition = applyCardinalSnap(to: rawPosition)

                    node.position = snappedPosition
                    node.syncDistanceFromPosition()
                }
                .onEnded { _ in
                    guard !isReadOnly else { return }
                    if isDragging {
                        isDragging = false
                        lastCardinalSnap = nil
                        onGestureEnd()
                    }
                }
        )
    }

    // MARK: - Cardinal Alignment & Auto-Snap Helper

    private func applyCardinalSnap(to rawPosition: CGPoint) -> CGPoint {
        let dx = rawPosition.x
        let dy = rawPosition.y
        let radius = hypot(dx, dy)

        guard radius > 15 else {
            lastCardinalSnap = nil
            return rawPosition
        }

        var angle = atan2(dy, dx) * 180 / .pi
        if angle < 0 { angle += 360 }

        let cardinalAngles = [0, 90, 180, 270]
        let tolerance: Double = 1.0

        var activeCardinal: Int?
        for cardinal in cardinalAngles {
            let diff = abs(angle - Double(cardinal))
            let minDiff = min(diff, 360 - diff)
            if minDiff <= tolerance {
                activeCardinal = cardinal
                break
            }
        }

        if let cardinal = activeCardinal {
            if lastCardinalSnap != cardinal {
                lastCardinalSnap = cardinal
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }

            switch cardinal {
            case 0:   return CGPoint(x: radius, y: 0)
            case 90:  return CGPoint(x: 0, y: radius)
            case 180: return CGPoint(x: -radius, y: 0)
            case 270: return CGPoint(x: 0, y: -radius)
            default:  return rawPosition
            }
        } else {
            lastCardinalSnap = nil
            return rawPosition
        }
    }
}

// MARK: - Helper Dashed Line Shape

struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        return path
    }
}

// MARK: - 1. Custom Shapes for Top-View Rendering

struct Trapezoid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topWidth = rect.width
        let bottomWidth = rect.width * 0.45
        let inset = (topWidth - bottomWidth) / 2.0

        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: topWidth, y: 0))
        path.addLine(to: CGPoint(x: topWidth - inset, y: rect.height))
        path.addLine(to: CGPoint(x: inset, y: rect.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - 2. Top-View Equipment Components

struct TopViewCameraShapeView: View {
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 5)
                .fill(DesignTokens.diagramNodeFill)
                .frame(width: 38, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(
                            isSelected ? DesignTokens.accentPrimary : DesignTokens.diagramStroke,
                            lineWidth: isSelected ? 2.0 : 1.5
                        )
                )
                .shadow(
                    color: isSelected ? DesignTokens.accentPrimary.opacity(0.4) : .clear,
                    radius: isSelected ? 5 : 2,
                    y: 2
                )
                .offset(y: 12)

            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected ? DesignTokens.accentPrimary : DesignTokens.diagramStroke)
                .frame(width: 18, height: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isSelected ? DesignTokens.accentPrimary : Color.clear, lineWidth: 1)
                )
                .offset(y: 0)
        }
        .frame(width: 44, height: 44)
    }
}

struct TopViewLightShapeView: View {
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Trapezoid()
                .fill(DesignTokens.diagramNodeFill)
                .frame(width: 38, height: 22)
                .overlay(
                    Trapezoid()
                        .stroke(
                            isSelected ? DesignTokens.accentPrimary : DesignTokens.diagramStroke,
                            lineWidth: isSelected ? 2.0 : 1.5
                        )
                )
                .shadow(
                    color: isSelected ? DesignTokens.accentPrimary.opacity(0.4) : .clear,
                    radius: isSelected ? 5 : 2,
                    y: 2
                )
                .offset(y: 2)

            Rectangle()
                .fill(isSelected ? DesignTokens.accentPrimary : DesignTokens.diagramStroke)
                .frame(width: 38, height: 3)
                .offset(y: 2)

            RoundedRectangle(cornerRadius: 3)
                .fill(DesignTokens.diagramStroke)
                .frame(width: 18, height: 14)
                .offset(y: 22)
        }
        .frame(width: 44, height: 44)
    }
}

struct TopViewAccessoryShapeView: View {
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 4)
                .fill(DesignTokens.diagramNodeFill)
                .frame(width: 50, height: 11)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            isSelected ? DesignTokens.accentPrimary : DesignTokens.diagramStroke,
                            lineWidth: isSelected ? 2.0 : 1.5
                        )
                )
                .shadow(
                    color: isSelected ? DesignTokens.accentPrimary.opacity(0.4) : .clear,
                    radius: isSelected ? 5 : 2,
                    y: 2
                )
                .offset(y: 11)

            Rectangle()
                .fill(isSelected ? DesignTokens.accentPrimary : DesignTokens.diagramStroke)
                .frame(width: 14, height: 4)
                .cornerRadius(1)
                .offset(y: 8)
        }
        .frame(width: 44, height: 44)
    }
}
