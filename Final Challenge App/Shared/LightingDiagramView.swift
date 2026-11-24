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

    // Smooth Zoom & Pan States
    @State private var zoomScale: CGFloat = 1.0
    @GestureState private var magnifyBy: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero

    // Scale Meter Visibility State
    @State private var showScaleMeter: Bool = false
    @State private var hideScaleMeterTask: Task<Void, Never>?
    var onNodeDragStart: ((Equipment) -> Void)?

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
        onNodeDragStart: ((Equipment) -> Void)? = nil
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
    }

    var body: some View {
        GeometryReader { geo in
            let subjectCenter = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let currentScale = zoomScale * magnifyBy
            let gridConfig = GridConfig.config(for: currentScale)

            // Dynamic distance threshold evaluated cleanly per gesture frame
            let minDistanceThreshold: Double = {
                if isExportedToPdf { return 0.05 }
                return max(0.15, 0.75 / Double(currentScale))
            }()

            ZStack {
                // Background Grid (Hides when isReadOnly is true)
                if !isReadOnly {
                    GridPattern(step: gridConfig.stepInPoints)
                        .stroke(DesignTokens.diagramGrid, lineWidth: 1 / currentScale)
                        .frame(width: 6000, height: 6000)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
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
                    style: StrokeStyle(lineWidth: 1 / currentScale, dash: [4 / currentScale, 3 / currentScale])
                )

                // Subject Card
                DiagramEntity(
                    title: "Subject",
                    icon: "person.fill",
                    position: subjectCenter,
                    currentScale: currentScale,
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
                        isSelected: selectedNodeId == node.id,
                        isReadOnly: isReadOnly,
                        zoomScale: currentScale,
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
                    .onChanged { _ in
                        guard !isReadOnly else { return }
                        hideScaleMeterTask?.cancel()
                        if !showScaleMeter {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showScaleMeter = true
                            }
                        }
                    }
                    .onEnded { value in
                        zoomScale *= value.magnification
                        zoomScale = max(0.3, min(zoomScale, 8.0))

                        guard !isReadOnly else { return }
                        hideScaleMeterTask?.cancel()
                        hideScaleMeterTask = Task {
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            if !Task.isCancelled {
                                await MainActor.run {
                                    withAnimation(.easeInOut(duration: 0.4)) {
                                        showScaleMeter = false
                                    }
                                }
                            }
                        }
                    }
            )
        }
        .clipped()
        .overlay(alignment: .topLeading) {
            if !isReadOnly {
                let activeScale = zoomScale * magnifyBy
                let activeConfig = GridConfig.config(for: activeScale)

                ScaleMeterView(
                    labelText: activeConfig.labelText,
                    barWidth: activeConfig.stepInPoints * activeScale
                )
                .padding(16)
                .opacity(showScaleMeter ? 1.0 : 0.0)
                .allowsHitTesting(false)
            }
        }
    }
}
