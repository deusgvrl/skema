import SwiftUI

/// Top-down lighting diagram, reused by Review, SetupDetail and the PDF (A10-10).

struct LightingDiagramView: View {
    @Bindable var viewModel: ReviewViewModel
    var isReadOnly: Bool = false
    var undoManager: UndoManager? = nil
    var onNodeTap: ((Equipment) -> Void)? = nil
    var onSubjectTap: (() -> Void)? = nil
    
    @State private var nodesSnapshot: [Equipment] = []
    @State private var selectedNodeId: UUID? = nil
    
    // Smooth Zoom & Pan States
    @State private var zoomScale: CGFloat = 1.0
    @GestureState private var magnifyBy: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geo in
            let subjectCenter = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
           
            ZStack {
                // Background Grid
                GridPattern()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    .frame(width: 6000, height: 6000)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                 
                // Connecting Lines
                Path { path in
                    for node in viewModel.nodes {
                        path.move(to: subjectCenter)
                        path.addLine(to: CGPoint(x: subjectCenter.x + node.position.x, y: subjectCenter.y + node.position.y))
                    }
                }
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                 
                // Distance Labels
                ForEach($viewModel.nodes) { $node in
                    let nodeScreenPos = CGPoint(x: subjectCenter.x + node.position.x, y: subjectCenter.y + node.position.y)
                    let midPoint = CGPoint(
                        x: (subjectCenter.x + nodeScreenPos.x) / 2,
                        y: (subjectCenter.y + nodeScreenPos.y) / 2
                    )
                     
                    Text("\(node.distance) m")
                        .font(.caption)
                        .padding(4)
                        .background(Color(uiColor: .systemBackground).opacity(0.8))
                        .cornerRadius(4)
                        .position(midPoint)
                }
                 
                // Subject
                DiagramEntity(title: "Subject", icon: "person.fill", position: subjectCenter) {
                    if !isReadOnly {
                        onSubjectTap?()
                    }
                }
                 
                // Draggable Nodes
                ForEach($viewModel.nodes) { $node in
                    NodeView(
                        node: $node,
                        subjectCenter: subjectCenter,
                        isSelected: !isReadOnly && selectedNodeId == node.id,
                        zoomScale: zoomScale * magnifyBy,
                        onTap: {
                            onNodeTap?(node)
                        },
                        onLongPress: {
                            if !isReadOnly {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedNodeId = node.id
                                }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                        },
                        onGestureStart: {
                            if !isReadOnly {
                                nodesSnapshot = viewModel.nodes.map { $0.clone() }
                            }
                        },
                        onGestureEnd: {
                            if !isReadOnly {
                                viewModel.applyStateChange(oldNodes: nodesSnapshot, undoManager: undoManager)
                            }
                        }
                    )
                }
            }
            // Apply Pan Offset
            .offset(
                x: offset.width + dragOffset.width,
                y: offset.height + dragOffset.height
            )
            .scaleEffect(zoomScale * magnifyBy)
            .background(Color(uiColor: .systemBackground))
            .onTapGesture {
                if !isReadOnly {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedNodeId = nil
                    }
                }
            }
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        state = CGSize(
                            width: value.translation.width / zoomScale,
                            height: value.translation.height / zoomScale
                        )
                    }
                    .onEnded { value in
                        offset.width += value.translation.width / zoomScale
                        offset.height += value.translation.height / zoomScale
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($magnifyBy) { value, state, _ in
                        state = value.magnification
                    }
                    .onEnded { value in
                        zoomScale *= value.magnification
                        zoomScale = max(0.3, min(zoomScale, 4.0))
                    }
            )
        }
        .clipped()
        .overlay(alignment: .bottomLeading) {
            ScaleMeterView(zoomScale: zoomScale * magnifyBy)
                .padding(16)
        }
    }
}

struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 40
        for x in stride(from: 0, through: rect.width, by: step) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        for y in stride(from: 0, through: rect.height, by: step) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}

struct DiagramEntity: View {
    let title: String
    let icon: String
    let position: CGPoint
    var onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(uiColor: .systemGray5))
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: icon).foregroundStyle(.secondary).font(.title3))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .position(position)
        .onTapGesture {
            onTap()
        }
    }
}

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
    
    
    // Haptic State
    @State private var lastHapticAngle: Double = 0.0
    @State private var feedbackGenerator: UISelectionFeedbackGenerator? = nil
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                ZStack {
                    switch node.category {
                    case .camera:
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(uiColor: .systemGray5))
                            .frame(width: 44, height: 44)
                            .overlay(Image(systemName: "camera.fill").foregroundStyle(isSelected ? .blue : .secondary).font(.title3))
                            .shadow(color: isSelected ? .blue.opacity(0.4) : .black.opacity(0.1), radius: isSelected ? 5 : 2, y: 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.8), lineWidth: isSelected ? 2.0 : 1.5)
                            )
                            .overlay( // Direction marker
                                Rectangle()
                                    .fill(Color(uiColor: .darkGray))
                                    .frame(width: 12, height: 6)
                                    .offset(y: -25)
                            )
                            
                    case .light:
                        LightShape()
                            .fill(Color(uiColor: .systemGray5))
                            .frame(width: 40, height: 40)
                            .shadow(color: isSelected ? .blue.opacity(0.4) : .black.opacity(0.1), radius: isSelected ? 5 : 2, y: 2)
                            .overlay(
                                LightShape()
                                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.8), lineWidth: isSelected ? 2.0 : 1.5)
                            )
                            .overlay( // Direction marker
                                Rectangle()
                                    .fill(Color(uiColor: .darkGray))
                                    .frame(width: 12, height: 6)
                                    .offset(y: -23)
                            )
                            
                    case .accessory:
                        Circle()
                            .fill(Color(uiColor: .systemGray5))
                            .frame(width: 36, height: 36)
                            .shadow(color: isSelected ? .blue.opacity(0.4) : .black.opacity(0.1), radius: isSelected ? 5 : 2, y: 2)
                            .overlay(
                                Circle()
                                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.8), lineWidth: isSelected ? 2.0 : 1.5)
                            )
                            .overlay( // Direction marker
                                Rectangle()
                                    .fill(Color(uiColor: .darkGray))
                                    .frame(width: 12, height: 6)
                                    .offset(y: -21)
                            )
                    }
                    
                    // Rotation Handle Button
                    if isSelected {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.blue)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color(uiColor: .systemBackground)).shadow(color: .black.opacity(0.15), radius: 2, y: 1))
                            .offset(y: -42)
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
        .background(Color.white.opacity(0.001)) // Hitbox for tap/drag
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
                    
                    let newX = dragStartPosition.x + canvasDeltaX
                    let newY = dragStartPosition.y + canvasDeltaY
                    
                    node.position = CGPoint(x: newX, y: newY)
                    
                    node.syncDistanceFromPosition()
                }
                .onEnded { _ in
                    if isDragging {
                        isDragging = false
                        onGestureEnd()
                    }
                }
        )    }
}

struct LightShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width * 0.8, y: 0))
        path.addLine(to: CGPoint(x: rect.width * 0.2, y: 0))
        path.closeSubpath()
        return path
    }
}

struct ScaleMeterView: View {
    var zoomScale: CGFloat
    
    var body: some View {
        let baseMeters: CGFloat = 1.0
        let calculatedMeters = baseMeters / zoomScale
        
        
        let labelText: String = {
            if calculatedMeters < 1.0 {
                let cm = Int(calculatedMeters * 100)
                return "\(max(1, cm)) cm"
            } else if calculatedMeters >= 10.0 {
                return "\(Int(round(calculatedMeters))) m"
            } else {
                return String(format: "%.1f m", calculatedMeters)
            }
        }()
        
        VStack(spacing: 3) {
            Text(labelText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            
            // Scale bar ticks and line matching your screenshot
            HStack(spacing: 0) {
                Rectangle()
                    .frame(width: 1.5, height: 8)
                    .foregroundStyle(.secondary)
                
                Rectangle()
                    .frame(height: 1.5)
                    .foregroundStyle(.secondary)
                
                Rectangle()
                    .frame(width: 1.5, height: 8)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 90)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

#Preview {
   LightingDiagramView(viewModel: ReviewViewModel(), isReadOnly: false, undoManager: nil)
}
