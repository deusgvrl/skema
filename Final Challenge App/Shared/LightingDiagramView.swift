import SwiftUI

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
                    .stroke(DesignTokens.diagramGrid, lineWidth: 1 / currentScale)
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
                    DesignTokens.diagramGuide,
                    style: StrokeStyle(lineWidth: 1 / currentScale, dash: [4 / currentScale, 3 / currentScale])
                )
                 
                // Subject card, under the distance labels so short distances stay readable
                DiagramEntity(
                    title: "Subject",
                    icon: "person.fill",
                    position: subjectCenter,
                    currentScale: currentScale
                ) {
                    onSubjectTap?()
                }
                 
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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .fixedSize()
                        .rotationEffect(.degrees(angle))
                        .scaleEffect(1 / currentScale)
                        .position(labelPos)
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
            .background(DesignTokens.pageBackground)
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

#Preview {
    LightingDiagramView(viewModel: ReviewViewModel(), isReadOnly: false, undoManager: nil)
}
