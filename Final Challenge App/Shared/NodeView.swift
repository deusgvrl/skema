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
    var zoomScale: CGFloat = 1.0
    
    var onTap: () -> Void
    var onLongPress: () -> Void
    var onGestureStart: () -> Void
    var onGestureEnd: () -> Void
    
    @State private var isRotating = false
    @State private var isDragging = false
    @State private var globalCenter: CGPoint = .zero
    @State private var dragStartPosition: CGPoint = .zero
    
    // Rotation Haptic State
    @State private var lastHapticAngle: Double = 0.0
    @State private var feedbackGenerator: UISelectionFeedbackGenerator? = nil
    
    // Cardinal Alignment Drag Haptic State (12, 3, 6, 9 o'clock)
    @State private var lastCardinalSnap: Int? = nil
    
    var body: some View {
        ZStack {
            // 1. Rotating Equipment Shape & Handle
            ZStack {
                switch node.category {
                case .camera:
                    TopViewCameraShapeView(isSelected: isSelected)
                    
                case .light:
                    TopViewLightShapeView(isSelected: isSelected)
                    
                case .accessory:
                    TopViewAccessoryShapeView(isSelected: isSelected)
                }
                
                // Rotation Handle Button
                if isSelected {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DesignTokens.accentPrimary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(uiColor: .systemBackground)).shadow(color: .black.opacity(0.15), radius: 2, y: 1))
                        .offset(y: -44)
                        .transition(.scale.combined(with: .opacity))
                        .highPriorityGesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    if !isRotating {
                                        isRotating = true
                                        onGestureStart()
                                        
                                        feedbackGenerator = UISelectionFeedbackGenerator()
                                        feedbackGenerator?.prepare()
                                        lastHapticAngle = node.rotationAngle
                                    }
                                    let dx = value.location.x - globalCenter.x
                                    let dy = value.location.y - globalCenter.y
                                    
                                    var visualAngle = (atan2(dy, dx) * 180 / .pi) + 90
                                    if visualAngle < 0 { visualAngle += 360 }
                                    
                                    let step = 3.0
                                    let currentStep = Int(visualAngle / step)
                                    let lastStep = Int(lastHapticAngle / step)
                                    
                                    if currentStep != lastStep {
                                        feedbackGenerator?.selectionChanged()
                                        feedbackGenerator?.prepare()
                                        lastHapticAngle = visualAngle
                                    }
                                    
                                    node.rotationAngle = visualAngle
                                    node.syncHorizontalAimFromRotation()
                                }
                                .onEnded { _ in
                                    if isRotating {
                                        isRotating = false
                                        onGestureEnd()
                                        feedbackGenerator = nil
                                    }
                                }
                        )
                }
            }
            .rotationEffect(.degrees(node.rotationAngle))
            
            // Rotation Angle Tooltip
            if isRotating {
                let displayAngle = (360 - Int(node.rotationAngle)) % 360
                
                Text("\(displayAngle)°")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .offset(x: 60, y: -15)
            }
        }
        .frame(width: 44, height: 44) // Locks 44x44 center 1:1 with node.position
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
        // 2. Hang Text Label below without altering the 44x44 icon's geometric center
        .overlay(alignment: .bottom) {
            Text(node.role.isEmpty ? node.name : "\(node.label) \(node.role)")
                .font(.caption2)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundColor(isSelected ? DesignTokens.accentPrimary : .primary)
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
        .onLongPressGesture(minimumDuration: 0.5) {
            if !isRotating { onLongPress() }
        }
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    guard isSelected, !isRotating else { return }
                    
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
        
        var activeCardinal: Int? = nil
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
                .fill(Color(uiColor: .systemGray5))
                .frame(width: 38, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(
                            isSelected ? DesignTokens.accentPrimary : Color.gray.opacity(0.8),
                            lineWidth: isSelected ? 2.0 : 1.5
                        )
                )
                .shadow(
                    color: isSelected ? DesignTokens.accentPrimary.opacity(0.4) : .black.opacity(0.12),
                    radius: isSelected ? 5 : 2,
                    y: 2
                )
                .offset(y: 12)

            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected ? DesignTokens.accentPrimary : DesignTokens.glassCardFill)
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
                .fill(Color(uiColor: .systemGray5))
                .frame(width: 38, height: 22)
                .overlay(
                    Trapezoid()
                        .stroke(
                            isSelected ? DesignTokens.accentPrimary : Color.gray.opacity(0.8),
                            lineWidth: isSelected ? 2.0 : 1.5
                        )
                )
                .shadow(
                    color: isSelected ? DesignTokens.accentPrimary.opacity(0.4) : .black.opacity(0.12),
                    radius: isSelected ? 5 : 2,
                    y: 2
                )
                .offset(y: 2)

            Rectangle()
                .fill(isSelected ? DesignTokens.accentPrimary : DesignTokens.glassCardFill)
                .frame(width: 38, height: 3)
                .offset(y: 2)

            RoundedRectangle(cornerRadius: 3)
                .fill(DesignTokens.glassCardFill)
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
                .fill(Color(uiColor: .systemGray5))
                .frame(width: 50, height: 11)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            isSelected ? DesignTokens.accentPrimary : Color.gray.opacity(0.8),
                            lineWidth: isSelected ? 2.0 : 1.5
                        )
                )
                .shadow(
                    color: isSelected ? DesignTokens.accentPrimary.opacity(0.4) : .black.opacity(0.12),
                    radius: isSelected ? 5 : 2,
                    y: 2
                )
                .offset(y: 11)

            Rectangle()
                .fill(isSelected ? DesignTokens.accentPrimary : DesignTokens.glassCardFill)
                .frame(width: 14, height: 4)
                .cornerRadius(1)
                .offset(y: 8)
        }
        .frame(width: 44, height: 44)
    }
}
