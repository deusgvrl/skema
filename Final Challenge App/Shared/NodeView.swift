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

    private let defaultHandleDistance: CGFloat = 72.0

    // Rotation Haptic & Snapping States
    @State private var lastHapticAngle: Double = 0.0
    @State private var feedbackGenerator: UISelectionFeedbackGenerator?
    @State private var lastRotationSnap: Int?

    @State private var currentHandleDistance: CGFloat = 72.0
    @State private var grabOffset: CGFloat = 0

    // Cardinal Alignment Drag Haptic State (12, 3, 6, 9 o'clock)
    @State private var lastCardinalSnap: Int?

    var body: some View {
        ZStack {
            // 1. Unified Equipment Image Asset & Rotation Handle Controls
            ZStack {
                if node.category == .light {
                    LightBeamConeView(colorTemp: node.colorTemp)
                }

                EquipmentNodeIconView(category: node.category, isSelected: isSelected)

                // Directional Pointer Ray & Front Rotate Handle
                if isSelected && !isReadOnly {
                    let lineLength = max(10, currentHandleDistance - 48)

                    DashedLine()
                        .stroke(DesignTokens.accentPrimary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 2, height: lineLength)
                        .offset(y: -(currentHandleDistance + 4) / 2)
                        .shadow(color: DesignTokens.accentPrimary.opacity(0.3), radius: 2)

                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DesignTokens.accentPrimary)
                        .offset(y: -currentHandleDistance + 20)
                        .shadow(color: DesignTokens.accentPrimary.opacity(0.4), radius: 2)

                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(DesignTokens.accentPrimary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(DesignTokens.diagramNodeFill)
                                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                        )
                        .overlay(Circle().stroke(DesignTokens.accentPrimary, lineWidth: 1.5))
                        .offset(y: -currentHandleDistance)
                        .transition(.scale.combined(with: .opacity))
                        .highPriorityGesture(rotationGesture)
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
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { updateGlobalCenter(geo) }
                    .onChange(of: geo.frame(in: .global)) { _, _ in updateGlobalCenter(geo) }
            }
        )
        .overlay(alignment: .bottom) {
            HStack(spacing: 4) {
                // 1. Primary Name (e.g. "Sony" or "W100")
                Text(node.name.isEmpty ? "Equipment" : node.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(DesignTokens.textPrimary)

                // 2. Role Subtitle on the same level (e.g. "- Camera 2")
                if zoomScale >= 1.75 && !node.role.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textPrimary)

                    Text(node.role)
                        .font(.caption)
                        .fontWeight(isSelected ? .bold : .regular)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .fixedSize()
            .offset(y: 30)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: zoomScale >= 1.75)
        }
        .scaleEffect(1 / zoomScale)
        .position(x: subjectCenter.x + node.position.x, y: subjectCenter.y + node.position.y)
        .highPriorityGesture(TapGesture().onEnded { if !isRotating { onTap() } })
        .gesture(isReadOnly ? nil : dragGesture)
    }

    // MARK: - Gestures & Helpers

    private var rotationGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let deltaX = value.location.x - globalCenter.x
                let deltaY = value.location.y - globalCenter.y
                let fingerDistance = hypot(deltaX, deltaY)

                if !isRotating {
                    isRotating = true
                    onGestureStart()
                    grabOffset = fingerDistance - currentHandleDistance
                    feedbackGenerator = UISelectionFeedbackGenerator()
                    feedbackGenerator?.prepare()
                    lastHapticAngle = node.rotationAngle
                }

                currentHandleDistance = max(defaultHandleDistance, fingerDistance - grabOffset)

                var visualAngle = (atan2(deltaY, deltaX) * 180 / .pi) + 90
                if visualAngle < 0 { visualAngle += 360 }

                // Apply 45° angle snapping
                let finalAngle = applyRotationSnap(to: visualAngle)

                // Selection haptics for smooth continuous drag outside snap zones
                if lastRotationSnap == nil {
                    let step = 3.0
                    if Int(finalAngle / step) != Int(lastHapticAngle / step) {
                        feedbackGenerator?.selectionChanged()
                        feedbackGenerator?.prepare()
                        lastHapticAngle = finalAngle
                    }
                }

                node.rotationAngle = finalAngle
                node.syncHorizontalAimFromRotation()
            }
            .onEnded { _ in
                guard isRotating else { return }
                isRotating = false
                lastRotationSnap = nil
                grabOffset = 0
                onGestureEnd()
                feedbackGenerator = nil
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    currentHandleDistance = defaultHandleDistance
                }
            }
    }

    private var dragGesture: some Gesture {
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

                let rawPosition = CGPoint(x: dragStartPosition.x + canvasDeltaX, y: dragStartPosition.y + canvasDeltaY)
                node.position = applyCardinalSnap(to: rawPosition)
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
            let normalizedDiff = min(diff, 360.0 - diff)

            if normalizedDiff <= tolerance {
                if lastRotationSnap != target {
                    lastRotationSnap = target
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                return Double(target)
            }
        }

        lastRotationSnap = nil
        return rawAngle
    }

    private func applyCardinalSnap(to rawPosition: CGPoint) -> CGPoint {
        let radius = hypot(rawPosition.x, rawPosition.y)
        guard radius > 15 else {
            lastCardinalSnap = nil
            return rawPosition
        }

        var angle = atan2(rawPosition.y, rawPosition.x) * 180 / .pi
        if angle < 0 { angle += 360 }

        guard let cardinal = closestCardinalAngle(for: angle, tolerance: 1.0) else {
            lastCardinalSnap = nil
            return rawPosition
        }

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
    }

    private func closestCardinalAngle(for angle: Double, tolerance: Double) -> Int? {
        let cardinalAngles = [0, 90, 180, 270]
        return cardinalAngles.first { cardinal in
            let diff = abs(angle - Double(cardinal))
            return min(diff, 360 - diff) <= tolerance
        }
    }
}// MARK: - Helper Dashed Line Shape

struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        return path
    }
}

struct EquipmentNodeIconView: View {
    let category: EquipmentCategory
    let isSelected: Bool

    var body: some View {
        Image(category.imageName(isSelected: isSelected))
            .resizable()
            .scaledToFit()
            .frame(width: category.iconSize.width, height: category.iconSize.height)
    }
}

struct LightBeamConeView: View {
    let colorTemp: String

    private var lightColor: Color {
        Color.kelvinColor(from: colorTemp)
    }

    var body: some View {
        ZStack {
            // 1. Soft Volumetric Outer Spread
            LightBeamShape()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: lightColor.opacity(0.85), location: 0.0),
                            .init(color: lightColor.opacity(0.40), location: 0.4),
                            .init(color: lightColor.opacity(0.10), location: 0.8),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 84, height: 96)
                .blur(radius: 4) // Soft atmospheric glow edge

            // 2. Focused Core Hotspot Beam
            LightBeamShape()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.9), location: 0.0),
                            .init(color: lightColor.opacity(0.6), location: 0.3),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 48, height: 75)
                .blur(radius: 1.5)
        }
        .offset(y: -55) // Positions beam in front of the lamp head
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// Trapezoid Shape representing the projected beam cone
struct LightBeamShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let originWidth: CGFloat = 16 // Narrow origin at lamp head
        let beamWidth: CGFloat = rect.width // Wide beam spread at end
        let originInset = (beamWidth - originWidth) / 2

        path.move(to: CGPoint(x: originInset, y: rect.maxY))
        path.addLine(to: CGPoint(x: beamWidth - originInset, y: rect.maxY))
        path.addLine(to: CGPoint(x: beamWidth, y: rect.minY))
        path.addLine(to: CGPoint(x: 0, y: rect.minY))
        path.closeSubpath()

        return path
    }
}
