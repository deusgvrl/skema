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

    // Snap Haptic & State (45° Increments)
    @State private var snapFeedback: UIImpactFeedbackGenerator?
    @State private var lastRotationSnap: Int?

    @State private var currentHandleDistance: CGFloat = 72.0
    @State private var grabOffset: CGFloat = 0

    // Cardinal Alignment Drag Haptic State
    @State private var lastCardinalSnap: Int?

    var body: some View {
        ZStack {
            ZStack {
                if node.category == .light {
                    LightBeamConeView(colorTemp: node.colorTemp)
                }

                EquipmentNodeIconView(
                    category: node.category,
                    accessoryType: node.accessoryType,
                    isSelected: isSelected
                )

                // Directional Pointer Ray & Front Rotate Handle
                if isSelected && !isReadOnly {
                    let lineLength = max(10, currentHandleDistance - 48)

                    DashedLine()
                        .stroke(DesignTokens.accentPrimary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 2, height: lineLength)
                        .offset(y: -(currentHandleDistance + 4) / 2)
                        .shadow(color: DesignTokens.accentPrimary.opacity(0.3), radius: 2)

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
        .overlay(alignment: .top) {
            VStack(spacing: 2) {
                // 1. Primary Name
                Text(node.name.isEmpty ? "Equipment" : node.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(DesignTokens.textPrimary)

                // 2. Secondary Specifications Subtitle (Visible when zoomed in)
                if zoomScale >= 1.75 {
                    categoryDetailsView
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .top)))

                    heightDetailsView
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .top)))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .fixedSize()
            .offset(y: node.category == .accessory ? 40 : 54)
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

                    // Prepare impact generator once when rotation starts
                    snapFeedback = UIImpactFeedbackGenerator(style: .medium)
                    snapFeedback?.prepare()
                }

                currentHandleDistance = max(defaultHandleDistance, fingerDistance - grabOffset)

                var visualAngle = (atan2(deltaY, deltaX) * 180 / .pi) + 90
                if visualAngle < 0 { visualAngle += 360 }

                // Apply 45° angle snapping (triggers snapFeedback only when snapping)
                let finalAngle = applyRotationSnap(to: visualAngle)

                node.rotationAngle = finalAngle
                node.syncHorizontalAimFromRotation()
            }
            .onEnded { _ in
                guard isRotating else { return }
                isRotating = false
                lastRotationSnap = nil
                grabOffset = 0
                onGestureEnd()

                snapFeedback = nil

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

                let rawPosition = CGPoint(
                    x: dragStartPosition.x + canvasDeltaX,
                    y: dragStartPosition.y + canvasDeltaY
                )
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
                    snapFeedback?.impactOccurred()
                    snapFeedback?.prepare()
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
}

// MARK: - Category Details Subview

extension NodeView {
    @ViewBuilder
    var categoryDetailsView: some View {
        switch node.category {
        case .camera:
            cameraDetailsView
        case .light:
            lightDetailsView
        case .accessory:
            accessoryDetailsView
        }
    }

    @ViewBuilder
    private var cameraDetailsView: some View {
        let hasLens = !node.lens.trimmingCharacters(in: .whitespaces).isEmpty
        let hasIso = !node.iso.trimmingCharacters(in: .whitespaces).isEmpty
        let hasAperture = !node.aperture.trimmingCharacters(in: .whitespaces).isEmpty

        if hasLens || hasIso || hasAperture {
            HStack(spacing: 4) {
                if hasLens {
                    Text(node.lens.lowercased().contains("mm") ? node.lens : "\(node.lens) mm")
                }
                if hasAperture {
                    if hasLens {
                        Text("|").foregroundStyle(DesignTokens.textSecondary)
                    }
                    Text(node.aperture)
                }
                if hasIso {
                    if hasLens || hasAperture {
                        Text("|").foregroundStyle(DesignTokens.textSecondary)
                    }
                    Text(node.iso.lowercased().contains("iso") ? node.iso : "ISO \(node.iso)")
                }
            }
            .font(.caption2)
            .foregroundStyle(DesignTokens.textSecondary)
        }
    }

    @ViewBuilder
    private var lightDetailsView: some View {
        if !node.power.trimmingCharacters(in: .whitespaces).isEmpty {
            Text(node.power)
                .font(.caption2)
                .foregroundStyle(DesignTokens.textSecondary)
        }
    }

    @ViewBuilder
    private var accessoryDetailsView: some View {
        if !node.role.trimmingCharacters(in: .whitespaces).isEmpty {
            Text(node.role)
                .font(.caption2)
                .foregroundStyle(DesignTokens.textSecondary)
        }
    }

    @ViewBuilder
    var heightDetailsView: some View {
        let trimmedHeight = node.height.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHeight.isEmpty {
            let heightText = trimmedHeight.lowercased().contains("m") ? trimmedHeight : "\(trimmedHeight) m"
            Text("H: \(heightText)")
                .font(.caption2)
                .foregroundStyle(DesignTokens.textSecondary)
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

struct EquipmentNodeIconView: View {
    let category: EquipmentCategory
    var accessoryType: AccessoryType = .reflector
    let isSelected: Bool

    var body: some View {
        Image(category.imageName(isSelected: isSelected, accessoryType: accessoryType))
            .resizable()
            .scaledToFit()
            .frame(width: category.iconSize.width, height: category.iconSize.height)
    }
}
