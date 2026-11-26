import SwiftUI

struct LightingDiagramView: View {
    @Bindable var viewModel: ReviewViewModel
    var isReadOnly: Bool = false
    var isExportedToPdf: Bool = false
    var undoManager: UndoManager?

    // Converted to Binding so parent controls selection lifecycle
    @Binding var selectedNodeId: UUID?
    var isSubjectSelected: Bool = false

    var onNodeTap: ((Equipment) -> Void)?
    var onSubjectTap: (() -> Void)?
    var onEmptyTap: (() -> Void)?

    @State private var nodesSnapshot: [Equipment] = []
    @State private var subjectRotationStart: Double = 0

    // Smooth Zoom & Scale States
    @State private var zoomScale: CGFloat = 1.0

    // Scale Meter Visibility State
    var onNodeDragStart: ((Equipment) -> Void)?
    
    // Reported to the parent so it can render the scale meter in a safe-area-aware overlay.
    var onScaleMeterChange: ((ScaleMeterState?) -> Void)?

    // keep a task for hiding:
    @State private var hideScaleMeterTask: Task<Void, Never>?

    init(
        viewModel: ReviewViewModel,
        isReadOnly: Bool = false,
        isExportedToPdf: Bool = false,
        undoManager: UndoManager? = nil,
        selectedNodeId: Binding<UUID?> = .constant(nil),
        isSubjectSelected: Bool = false,
        initialZoomScale: CGFloat = 1.0,
        onNodeTap: ((Equipment) -> Void)? = nil,
        onSubjectTap: (() -> Void)? = nil,
        onEmptyTap: (() -> Void)? = nil,
        onNodeDragStart: ((Equipment) -> Void)? = nil,
        onScaleMeterChange:((ScaleMeterState?) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.isReadOnly = isReadOnly
        self.isExportedToPdf = isExportedToPdf
        self.undoManager = undoManager
        self._selectedNodeId = selectedNodeId
        self.isSubjectSelected = isSubjectSelected
        self._zoomScale = State(initialValue: initialZoomScale)
        self.onNodeTap = onNodeTap
        self.onSubjectTap = onSubjectTap
        self.onEmptyTap = onEmptyTap
        self.onNodeDragStart = onNodeDragStart
        self.onScaleMeterChange = onScaleMeterChange
    }

    private let canvasDimension: CGFloat = 3000

    var body: some View {
        let subjectCenter = CGPoint(x: canvasDimension / 2, y: canvasDimension / 2)
        let diagramScale = zoomScale
        let gridConfig = GridConfig.config(for: diagramScale)

        // Dynamic distance threshold evaluated cleanly per gesture frame
        let minDistanceThreshold: Double = {
            if isExportedToPdf { return 0.05 }
            return max(0.15, 0.75 / Double(diagramScale))
        }()

        let interactiveCenters: [CGPoint] = [subjectCenter] + viewModel.nodes.map {
            CGPoint(x: subjectCenter.x + $0.position.x, y: subjectCenter.y + $0.position.y)
        }

        ZoomableScrollView(
            zoomScale: $zoomScale,
            minScale: 0.3,
            maxScale: 8.0,
            canvasSize: CGSize(width: canvasDimension, height: canvasDimension),
            isReadOnly: isReadOnly,
            interactiveCenters: interactiveCenters,
            onEmptyTap: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedNodeId = nil
                }
                onEmptyTap?()
            },
            onZoomChanged: { scale in
                guard !isReadOnly else { return }
                hideScaleMeterTask?.cancel()
                let config = GridConfig.config(for: scale)
                onScaleMeterChange?(
                    ScaleMeterState(
                        labelText: config.labelText,
                        barWidth: config.stepInPoints * scale
                    )
                )
            },
            onZoomEnded: {
                guard !isReadOnly else { return }
                hideScaleMeterTask?.cancel()
                hideScaleMeterTask = Task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    if !Task.isCancelled {
                        await MainActor.run { onScaleMeterChange?(nil) }
                    }
                }
            },
            content: {
                ZStack {
                // Background Grid (Hides when isReadOnly is true)
                if !isReadOnly {
                    GridPattern(step: gridConfig.stepInPoints)
                        .stroke(DesignTokens.diagramGrid, lineWidth: 1 / diagramScale)
                        .frame(width: canvasDimension, height: canvasDimension)
                        .position(subjectCenter)
                }

                // Connecting Lines
                Path { path in
                    for node in viewModel.nodes where node.position != .zero {
                        path.move(to: subjectCenter)
                        let endPoint = CGPoint(
                            x: subjectCenter.x + node.position.x,
                            y: subjectCenter.y + node.position.y
                        )
                        path.addLine(to: endPoint)
                    }
                }
                .stroke(
                    DesignTokens.diagramGuide,
                    style: StrokeStyle(lineWidth: 1 / diagramScale, dash: [4 / diagramScale, 3 / diagramScale])
                )

                // Subject Card
                DiagramEntity(
                    title: "Subject",
                    icon: "person.fill",
                    position: subjectCenter,
                    currentScale: diagramScale,
                    isSelected: isSubjectSelected,
                    isReadOnly: isReadOnly,
                    rotationAngle: $viewModel.draftSetup.subjectRotationAngle,
                    onTap: { onSubjectTap?() },
                    onGestureStart: {
                        subjectRotationStart = viewModel.draftSetup.subjectRotationAngle
                    },
                    onGestureEnd: {
                        guard !isReadOnly else { return }
                        let finalAngle = viewModel.draftSetup.subjectRotationAngle
                        // Reset to the start value so the undo registration captures the real old value
                        viewModel.draftSetup.subjectRotationAngle = subjectRotationStart
                        viewModel.updateSubjectRotation(
                            oldValue: subjectRotationStart,
                            newValue: finalAngle,
                            undoManager: undoManager
                        )
                    }
                )

                // Distance Labels
                ForEach(Array(viewModel.nodes.enumerated()), id: \.element.id) { _, node in
                    let distanceValue = Double("\(node.distance)") ?? (hypot(node.position.x, node.position.y) / 100)

                    if node.position != .zero && distanceValue >= minDistanceThreshold {
                        let deltaX = node.position.x
                        let deltaY = node.position.y
                        let posX = subjectCenter.x + deltaX * 0.5
                        let posY = subjectCenter.y + deltaY * 0.5

                        let angle: Double = {
                            var rawAngle = atan2(deltaY, deltaX) * 180 / .pi
                            if rawAngle > 90 {
                                rawAngle -= 180
                            } else if rawAngle < -90 {
                                rawAngle += 180
                            }
                            return rawAngle
                        }()

                        Text("\(node.distance) m")
                            .font(.caption2.weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .fixedSize()
                            .rotationEffect(.degrees(angle))
                            .scaleEffect(1 / diagramScale)
                            .position(x: posX, y: posY)
                            .transition(.opacity)
                    }
                }

                // Draggable Nodes
                ForEach($viewModel.nodes) { $node in
                    NodeView(
                        node: $node,
                        subjectCenter: subjectCenter,
                        isSelected: selectedNodeId == node.id,
                        isReadOnly: isReadOnly,
                        zoomScale: diagramScale,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedNodeId = node.id
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onNodeTap?(node)
                        },
                        onGestureStart: {
                            if !isReadOnly {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedNodeId = node.id
                                }
                                onNodeDragStart?(node)
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
            .frame(width: canvasDimension, height: canvasDimension)
            .background(DesignTokens.pageBackground)
        }
        )
        .clipped()
    }
}
