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
            let currentScale = zoomScale * magnifyBy // Unified active zoom factor
            
            ZStack {
                // Background Grid
                GridPattern()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1 / currentScale)
                    .frame(width: 6000, height: 6000)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                 
                // Connecting Lines (Constant line thickness regardless of zoom)
                Path { path in
                    for node in viewModel.nodes {
                        path.move(to: subjectCenter)
                        path.addLine(to: CGPoint(x: subjectCenter.x + node.position.x, y: subjectCenter.y + node.position.y))
                    }
                }
                .stroke(
                    Color.secondary,
                    style: StrokeStyle(lineWidth: 1.5 / currentScale, dash: [5 / currentScale])
                )
                 
                // Distance Labels (Aligned, Offset, and Staggered)
                
                ForEach(Array(viewModel.nodes.enumerated()), id: \.element.id) { index, node in
                    let dx = node.position.x
                    let dy = node.position.y
                    let length = max(1.0, hypot(dx, dy))
                    
                    // 1. Stagger position ratio along the line (alternates 0.45 and 0.60 based on index)
                    let ratio: CGFloat = (index % 2 == 0) ? 0.45 : 0.60
                    let posX = subjectCenter.x + dx * ratio
                    let posY = subjectCenter.y + dy * ratio
                    
                    // 2. Calculate ray angle in degrees & keep text right-side-up (inside closure)
                    let angle: Double = {
                        var rawAngle = atan2(dy, dx) * 180 / .pi
                        if rawAngle > 90 {
                            rawAngle -= 180
                        } else if rawAngle < -90 {
                            rawAngle += 180
                        }
                        return rawAngle
                    }()
                    
                    // 3. Calculate perpendicular unit normal vector to offset text off the line
                    let normalX = -dy / length
                    let normalY = dx / length
                    let offsetDistance: CGFloat = 12 / currentScale // Counter-scaled offset
                    
                    let labelPos = CGPoint(
                        x: posX + normalX * offsetDistance,
                        y: posY + normalY * offsetDistance
                    )
                    
                    Text("\(node.distance) m")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(uiColor: .systemBackground).opacity(0.85))
                                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                        )
                        .rotationEffect(.degrees(angle)) // Aligns text along line direction
                        .scaleEffect(1 / currentScale)    // Counter-scales font size
                        .position(labelPos)
                }
                
                // Subject Icon (Constant icon & font size)
                DiagramEntity(
                    title: "Subject",
                    icon: "person.fill",
                    position: subjectCenter,
                    currentScale: currentScale
                ) {
                    onSubjectTap?()
                }
                 
                // Draggable Nodes
                ForEach($viewModel.nodes) { $node in
                    NodeView(
                        node: $node,
                        subjectCenter: subjectCenter,
                        isSelected: !isReadOnly && selectedNodeId == node.id,
                        zoomScale: currentScale,
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
            // Apply Canvas Pan Offset
            .offset(
                x: offset.width + dragOffset.width,
                y: offset.height + dragOffset.height
            )
            .scaleEffect(currentScale)
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
                            width: value.translation.width / currentScale,
                            height: value.translation.height / currentScale
                        )
                    }
                    .onEnded { value in
                        offset.width += value.translation.width / currentScale
                        offset.height += value.translation.height / currentScale
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
            let activeScale = zoomScale * magnifyBy
            ScaleMeterView(currentScale: activeScale)
                    .padding(16)
        }
    }
}

// Counter-scaled Diagram Entity (Subject)
struct DiagramEntity: View {
    let title: String
    let icon: String
    let position: CGPoint
    var currentScale: CGFloat = 1.0
    var onTap: () -> Void
    
    var body: some View {
        // 1. Core 44x44 icon box centered at position
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(uiColor: .systemGray5))
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .font(.title3)
            )
            // 2. Hang text label below without shifting the icon's center
            .overlay(alignment: .bottom) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(y: 20)
            }
            .scaleEffect(1 / currentScale) // Counter-scale icon and text
            .position(position)            // Now centers the 44x44 box exactly on the point
            .onTapGesture {
                onTap()
            }
    }
}

struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 50
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

struct ScaleMeterView: View {
    var currentScale: CGFloat
    
    var body: some View {
        // 50 points bar at pointsPerMeter = 100.0 represents 0.5m (50 cm) at 1.0x zoom
        let baseMeters: CGFloat = 0.5
        let calculatedMeters = baseMeters / currentScale
        
        let labelText: String = {
            if calculatedMeters < 1.0 {
                let cm = Int(round(calculatedMeters * 100))
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
            
            HStack(spacing: 0) {
                Rectangle().frame(width: 1.5, height: 8).foregroundStyle(.secondary)
                Rectangle().frame(height: 1.5).foregroundStyle(.secondary)
                Rectangle().frame(width: 1.5, height: 8).foregroundStyle(.secondary)
            }
            .frame(width: 50)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

#Preview {
   LightingDiagramView(viewModel: ReviewViewModel(), isReadOnly: false, undoManager: nil)
}
