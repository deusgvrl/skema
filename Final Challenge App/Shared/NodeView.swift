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
        VStack(spacing: 4) {
            ZStack {
                ZStack {
                    // Top-view shapes oriented with Front = UP (12 o'clock)
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
                            .foregroundColor(.blue)
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
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .offset(x: 60, y: -15)
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
            
            // Item Label
            Text(node.role.isEmpty ? node.name : "\(node.label) \(node.role)")
                .font(.caption2)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundColor(isSelected ? .blue : .primary)
                .lineLimit(1)
        }
        .background(Color.white.opacity(0.001))
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
                    
                    // 👈 Applies automatic snap positioning + haptic impulse
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
    
    /// Evaluates if position is within ±1.0° of 12, 3, 6, or 9 o'clock. Snaps coordinate exactly to axis and triggers haptic feedback.
    private func applyCardinalSnap(to rawPosition: CGPoint) -> CGPoint {
        let dx = rawPosition.x
        let dy = rawPosition.y
        let r = hypot(dx, dy)
        
        // Prevent snapping jitter when dragging near subject center
        guard r > 15 else {
            lastCardinalSnap = nil
            return rawPosition
        }
        
        // Calculate angle in degrees [0, 360) where 3 o'clock = 0°
        var angle = atan2(dy, dx) * 180 / .pi
        if angle < 0 { angle += 360 }
        
        let cardinalAngles = [0, 90, 180, 270] // 3, 6, 9, 12 o'clock
        let tolerance: Double = 1.0            // Snap window (±1.0°)
        
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
            // Trigger haptic when first entering snap zone
            if lastCardinalSnap != cardinal {
                lastCardinalSnap = cardinal
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            
            // Snap position directly to cardinal axis
            switch cardinal {
            case 0:   // 3 o'clock (0° -> +X axis)
                return CGPoint(x: r, y: 0)
            case 90:  // 6 o'clock (90° -> +Y axis)
                return CGPoint(x: 0, y: r)
            case 180: // 9 o'clock (180° -> -X axis)
                return CGPoint(x: -r, y: 0)
            case 270: // 12 o'clock (270° -> -Y axis)
                return CGPoint(x: 0, y: -r)
            default:
                return rawPosition
            }
        } else {
            lastCardinalSnap = nil
            return rawPosition
        }
    }
}

// MARK: - 1. Custom Shapes for Top-View Rendering

/// Trapezoid Shape used for Light reflector/softbox expansion facing Front (UP).
struct Trapezoid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topWidth = rect.width
        let bottomWidth = rect.width * 0.45
        let inset = (topWidth - bottomWidth) / 2.0
        
        // Front wide edge (Top)
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: topWidth, y: 0))
        // Back narrow edge (Bottom)
        path.addLine(to: CGPoint(x: topWidth - inset, y: rect.height))
        path.addLine(to: CGPoint(x: inset, y: rect.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - 2. Top-View Equipment Components

/// Top-view Camera: Large rectangle (Body) at back, small rectangle (Lens) extending to front.
struct TopViewCameraShapeView: View {
    let isSelected: Bool
    
    var body: some View {
        ZStack(alignment: .top) {
            // Camera Body (Back)
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(uiColor: .systemGray5))
                .frame(width: 38, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.8), lineWidth: isSelected ? 2.0 : 1.5)
                )
                .shadow(color: isSelected ? .blue.opacity(0.4) : .black.opacity(0.12), radius: isSelected ? 5 : 2, y: 2)
                .offset(y: 12)
            
            // Camera Lens (Front / UP)
            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected ? Color.blue : Color(uiColor: .darkGray))
                .frame(width: 18, height: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
                )
                .offset(y: 0)
        }
        .frame(width: 44, height: 44)
    }
}

/// Top-view Light: Trapezoid (Reflector/Softbox) facing front, small rectangle (Housing) at back.
struct TopViewLightShapeView: View {
    let isSelected: Bool
    
    var body: some View {
        ZStack(alignment: .top) {
            // Light Reflector / Softbox Cone (Front / UP)
            Trapezoid()
                .fill(Color(uiColor: .systemGray5))
                .frame(width: 38, height: 22)
                .overlay(
                    Trapezoid()
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.8), lineWidth: isSelected ? 2.0 : 1.5)
                )
                .shadow(color: isSelected ? .blue.opacity(0.4) : .black.opacity(0.12), radius: isSelected ? 5 : 2, y: 2)
                .offset(y: 2)
            
            // Front Aperture Line (Emphasizes direction)
            Rectangle()
                .fill(isSelected ? Color.blue : Color(uiColor: .darkGray))
                .frame(width: 38, height: 3)
                .offset(y: 2)
            
            // Light Housing Body (Back / DOWN)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(uiColor: .darkGray))
                .frame(width: 18, height: 14)
                .offset(y: 22)
        }
        .frame(width: 44, height: 44)
    }
}

/// Top-view Accessory: Clean single rectangle with front direction marker bar.
struct TopViewAccessoryShapeView: View {
    let isSelected: Bool
    
    var body: some View {
        ZStack(alignment: .top) {
            // Accessory Body
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(uiColor: .systemGray5))
                .frame(width: 50, height: 11)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.8), lineWidth: isSelected ? 2.0 : 1.5)
                )
                .shadow(color: isSelected ? .blue.opacity(0.4) : .black.opacity(0.12), radius: isSelected ? 5 : 2, y: 2)
                .offset(y: 11)
            
            // Front Direction Marker Accent (UP)
            Rectangle()
                .fill(isSelected ? Color.blue : Color(uiColor: .darkGray))
                .frame(width: 14, height: 4)
                .cornerRadius(1)
                .offset(y: 8)
        }
        .frame(width: 44, height: 44)
    }
}














