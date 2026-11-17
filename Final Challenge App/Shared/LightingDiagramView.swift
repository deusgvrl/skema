import SwiftUI

// MARK: - 1. Adaptive Grid Configuration Helper

struct GridConfig {
    let stepInPoints: CGFloat // Grid tile width in canvas model points
    let labelText: String     // Scale badge text (e.g. "25 cm", "50 cm", "1 m")
    
    /// Calculates the optimal grid subdivision step based on the active zoom factor
    static func config(for scale: CGFloat) -> GridConfig {
        // Target model distance that maps to roughly 50–70 screen pixels
        let targetMeters = 0.5 / scale
        
        if targetMeters <= 0.35 {
            // Zoomed In (scale >= 1.4x) -> 25 cm per tile (1.50m = 6 tiles)
            return GridConfig(stepInPoints: 25, labelText: "25 cm")
        } else if targetMeters <= 0.75 {
            // Standard View (0.67x <= scale < 1.4x) -> 50 cm per tile (1.50m = 3 tiles)
            return GridConfig(stepInPoints: 50, labelText: "50 cm")
        } else if targetMeters <= 1.5 {
            // Zoomed Out (0.33x <= scale < 0.67x) -> 1 meter per tile (1.50m = 1.5 tiles)
            return GridConfig(stepInPoints: 100, labelText: "1 m")
        } else {
            // Far Zoomed Out (scale < 0.33x) -> 2 meters per tile
            return GridConfig(stepInPoints: 200, labelText: "2 m")
        }
    }
}

// MARK: - 2. LightingDiagramView

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
    
    init(
        viewModel: ReviewViewModel,
        isReadOnly: Bool = false,
        undoManager: UndoManager? = nil,
        initialZoomScale: CGFloat = 1.0, // Default 1.0x = 50 cm scale
        onNodeTap: ((Equipment) -> Void)? = nil,
        onSubjectTap: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.isReadOnly = isReadOnly
        self.undoManager = undoManager
        self._zoomScale = State(initialValue: initialZoomScale)
        self.onNodeTap = onNodeTap
        self.onSubjectTap = onSubjectTap
    }
    
    var body: some View {
        GeometryReader { geo in
            let subjectCenter = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let currentScale = zoomScale * magnifyBy // Unified active zoom factor
            let gridConfig = GridConfig.config(for: currentScale) // Dynamic grid resolution
            
            ZStack {
                // Background Grid (Adapts step automatically)
                GridPattern(step: gridConfig.stepInPoints)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1 / currentScale)
                    .frame(width: 6000, height: 6000)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                 
                // Connecting Lines
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
                 
                // Distance Labels
                ForEach(Array(viewModel.nodes.enumerated()), id: \.element.id) { index, node in
                    let dx = node.position.x
                    let dy = node.position.y
                    let length = max(1.0, hypot(dx, dy))
                    
                    let ratio: CGFloat = (index % 2 == 0) ? 0.45 : 0.60
                    let posX = subjectCenter.x + dx * ratio
                    let posY = subjectCenter.y + dy * ratio
                    
                    let angle: Double = {
                        var rawAngle = atan2(dy, dx) * 180 / .pi
                        if rawAngle > 90 {
                            rawAngle -= 180
                        } else if rawAngle < -90 {
                            rawAngle += 180
                        }
                        return rawAngle
                    }()
                    
                    let normalX = -dy / length
                    let normalY = dx / length
                    let offsetDistance: CGFloat = 12 / currentScale
                    
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
                        .rotationEffect(.degrees(angle))
                        .scaleEffect(1 / currentScale)
                        .position(labelPos)
                }
                
                // Subject Icon (Centered on Grid Point)
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
            let activeConfig = GridConfig.config(for: activeScale)
            
            // Scale bar width matches 1 grid square on screen
            ScaleMeterView(
                labelText: activeConfig.labelText,
                barWidth: activeConfig.stepInPoints * activeScale
            )
            .padding(16)
        }
    }
}

// MARK: - 3. Supporting Components

struct DiagramEntity: View {
    let title: String
    let icon: String
    let position: CGPoint
    var currentScale: CGFloat = 1.0
    var onTap: () -> Void
    
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(uiColor: .systemGray5))
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .font(.title3)
            )
            .overlay(alignment: .bottom) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(y: 20)
            }
            .scaleEffect(1 / currentScale)
            .position(position)
            .onTapGesture {
                onTap()
            }
    }
}

struct GridPattern: Shape {
    var step: CGFloat = 50
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
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
    let labelText: String
    let barWidth: CGFloat
    
    var body: some View {
        VStack(spacing: 3) {
            Text(labelText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 0) {
                Rectangle().frame(width: 1.5, height: 8).foregroundStyle(.secondary)
                Rectangle().frame(height: 1.5).foregroundStyle(.secondary)
                Rectangle().frame(width: 1.5, height: 8).foregroundStyle(.secondary)
            }
            .frame(width: max(20, barWidth))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

#Preview {
    LightingDiagramView(viewModel: ReviewViewModel(), isReadOnly: false, undoManager: nil)
}
