import SwiftUI

struct LightingDiagramView: View {
    @Bindable var viewModel: ReviewViewModel
    var isReadOnly: Bool = false
    var isExportedToPdf: Bool = false
    var undoManager: UndoManager? = nil
    
    // 👈 1. Converted to Binding so parent controls selection lifecycle
    @Binding var selectedNodeId: UUID?
    
    var onNodeTap: ((Equipment) -> Void)? = nil
    var onSubjectTap: (() -> Void)? = nil
    var onEmptyTap: (() -> Void)? = nil
    
    @State private var nodesSnapshot: [Equipment] = []
    
    // Smooth Zoom & Pan States
    @State private var zoomScale: CGFloat = 1.0
    @GestureState private var magnifyBy: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero
    
    init(
        viewModel: ReviewViewModel,
        isReadOnly: Bool = false,
        isExportedToPdf: Bool = false,
        undoManager: UndoManager? = nil,
        selectedNodeId: Binding<UUID?> = .constant(nil), 
        initialZoomScale: CGFloat = 1.0,
        onNodeTap: ((Equipment) -> Void)? = nil,
        onSubjectTap: (() -> Void)? = nil,
        onEmptyTap: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.isReadOnly = isReadOnly
        self.isExportedToPdf = isExportedToPdf
        self.undoManager = undoManager
        self._selectedNodeId = selectedNodeId
        self._zoomScale = State(initialValue: initialZoomScale)
        self.onNodeTap = onNodeTap
        self.onSubjectTap = onSubjectTap
        self.onEmptyTap = onEmptyTap
    }
    
    var body: some View {
        GeometryReader { geo in
            let subjectCenter = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let currentScale = zoomScale * magnifyBy
            let gridConfig = GridConfig.config(for: currentScale)
            
            ZStack {
                // Background Grid
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
                 
                // Subject Card
                DiagramEntity(
                    title: "Subject",
                    icon: "person.fill",
                    position: subjectCenter,
                    currentScale: currentScale
                ) {
                    onSubjectTap?()
                }
                 
                // Distance Labels
                let minDistanceThreshold = 1.5 / currentScale

                ForEach(Array(viewModel.nodes.enumerated()), id: \.element.id) { index, node in
                    let distanceValue = Double("\(node.distance)") ?? (hypot(node.position.x, node.position.y) / 100)
                    
                    if isExportedToPdf || distanceValue >= minDistanceThreshold {
                        let dx = node.position.x
                        let dy = node.position.y
                        let posX = subjectCenter.x + dx * 0.5
                        let posY = subjectCenter.y + dy * 0.5
                        
                        let angle: Double = {
                            var rawAngle = atan2(dy, dx) * 180 / .pi
                            if rawAngle > 90 {
                                rawAngle -= 180
                            } else if rawAngle < -90 {
                                rawAngle += 180
                            }
                            return rawAngle
                        }()
                        
                        Text("\(node.distance) m")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignTokens.textSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(DesignTokens.pageBackground.opacity(0.9))
                            )
                            .fixedSize()
                            .rotationEffect(.degrees(angle))
                            .scaleEffect(1 / currentScale)
                            .position(x: posX, y: posY)
                            .transition(.opacity)
                    }
                }
                
                // Draggable Nodes
                ForEach($viewModel.nodes) { $node in
                    NodeView(
                        node: $node,
                        subjectCenter: subjectCenter,
                        isSelected: !isReadOnly && selectedNodeId == node.id,
                        zoomScale: currentScale,
                        onTap: {
                            if !isReadOnly {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedNodeId = node.id
                                }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                            onNodeTap?(node)
                        },
                        onGestureStart: {
                            if !isReadOnly {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedNodeId = node.id
                                }
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
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedNodeId = nil
                }
                onEmptyTap?()
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
                        zoomScale = max(0.3, min(zoomScale, 8.0))
                    }
            )
        }
        .clipped()
        .overlay(alignment: .topLeading) {
            let activeScale = zoomScale * magnifyBy
            let activeConfig = GridConfig.config(for: activeScale)
            
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
