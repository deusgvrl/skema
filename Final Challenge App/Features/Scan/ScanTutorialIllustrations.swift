//
//  ScanTutorialIllustrations.swift
//  Final Challenge App
//
//  Small looping drawings, one per tutorial step, in the diagram's style. With Reduce Motion on,
//  each shows its finished state without moving.
//

import SwiftUI

struct ScanTutorialIllustration: View {
    let step: ScanTutorialStep

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            DesignTokens.pageBackground
            GridPattern(step: 24)
                .stroke(DesignTokens.diagramGrid, lineWidth: 1)
            switch step {
            case .tapSubject: TapSubjectDrawing(animates: !reduceMotion)
            case .showFloor: ShowFloorDrawing(animates: !reduceMotion)
            case .walkToEachItem: WalkToItemsDrawing(animates: !reduceMotion)
            case .finish: FinishDrawing(animates: !reduceMotion)
            }
        }
        .clipShape(.rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(DesignTokens.diagramSubjectBorder, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

// MARK: - Shared pieces

/// Loops through `phases` (or sits on the last one when `animates` is false).
private struct Looping<Phase: Equatable, Content: View>: View {
    let phases: [Phase]
    let animates: Bool
    @ViewBuilder let content: (Phase) -> Content

    var body: some View {
        if animates {
            PhaseAnimator(phases) { phase in
                content(phase)
            } animation: { _ in
                .easeInOut(duration: 0.7).delay(0.35)
            }
        } else if let last = phases.last {
            content(last)
        }
    }
}

private struct SubjectCard: View {
    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 4)
                .fill(DesignTokens.nodeDetailFill)
                .frame(width: 12, height: 20)
            Text("Subject")
                .font(.caption2)
                .foregroundStyle(DesignTokens.textPrimary)
        }
        .frame(width: 70, height: 50)
        .background(DesignTokens.diagramSubjectFill, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DesignTokens.diagramSubjectBorder, lineWidth: 1))
    }
}

private struct CapturedTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DesignTokens.detectedGreen, in: .capsule)
    }
}

/// An iPhone seen from above or from the side.
private struct PhoneShape: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(DesignTokens.diagramStroke, lineWidth: 2)
            .background(DesignTokens.diagramNodeFill, in: .rect(cornerRadius: 6))
            .frame(width: 24, height: 44)
    }
}

// MARK: - 1. Tap your product

private struct TapSubjectDrawing: View {
    let animates: Bool

    var body: some View {
        Looping(phases: [0, 1, 2], animates: animates) { phase in
            ZStack {
                SubjectCard()
                Circle()
                    .stroke(DesignTokens.accentPrimary, lineWidth: 2)
                    .frame(width: 44, height: 44)
                    .scaleEffect(phase == 1 ? 1.6 : 0.5)
                    .opacity(phase == 1 ? 1 : 0)
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .offset(x: phase == 0 ? 60 : 18, y: phase == 0 ? 70 : 30)
                CapturedTag(text: "Subject ✓")
                    .offset(y: -44)
                    .opacity(phase == 2 ? 1 : 0)
                    .scaleEffect(phase == 2 ? 1 : 0.8)
            }
        }
    }
}

// MARK: - 2. Show the floor

private struct ShowFloorDrawing: View {
    let animates: Bool

    var body: some View {
        Looping(phases: [false, true], animates: animates) { tilted in
            GeometryReader { geometry in
                let floorY = geometry.size.height * 0.78
                ZStack {
                    // Floor, highlighted once the phone looks at it.
                    Rectangle()
                        .fill(tilted ? DesignTokens.detectedGreen.opacity(0.18) : .clear)
                        .frame(height: geometry.size.height - floorY)
                        .position(x: geometry.size.width / 2, y: floorY + (geometry.size.height - floorY) / 2)
                    Rectangle()
                        .fill(tilted ? DesignTokens.detectedGreen : DesignTokens.diagramStroke)
                        .frame(height: 2)
                        .position(x: geometry.size.width / 2, y: floorY)
                    // The view from the phone.
                    ViewCone()
                        .fill(DesignTokens.accentPrimary.opacity(0.15))
                        .frame(width: 140, height: 90)
                        .rotationEffect(.degrees(tilted ? 55 : 0), anchor: .leading)
                        .position(x: geometry.size.width * 0.3 + 70, y: geometry.size.height * 0.42)
                    // Side view, camera facing right: tilting down turns the top of the phone toward the floor.
                    PhoneShape()
                        .rotationEffect(.degrees(tilted ? 35 : 0))
                        .position(x: geometry.size.width * 0.3, y: geometry.size.height * 0.42)
                    CapturedTag(text: "Floor ✓")
                        .position(x: geometry.size.width * 0.68, y: floorY + 22)
                        .opacity(tilted ? 1 : 0)
                }
            }
        }
    }
}

/// A wedge opening to the right from the middle of its left edge.
private struct ViewCone: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - 3. Walk up to each light and camera

/// Top-down: the phone walks up close to one item after another, staying in front of the set
/// (it never goes around the back of the subject), and each item turns green once it's close.
private struct WalkToItemsDrawing: View {
    let animates: Bool

    private struct Item {
        let position: CGPoint
        let isCamera: Bool
        /// Where the phone stands to measure it, and which way it faces (0 = up).
        let stop: CGPoint
        let facing: Double
    }

    private let items: [Item] = [
        Item(position: CGPoint(x: -120, y: 95), isCamera: true, stop: CGPoint(x: -62, y: 95), facing: -90),
        Item(position: CGPoint(x: -110, y: -25), isCamera: false, stop: CGPoint(x: -110, y: 35), facing: 0),
        Item(position: CGPoint(x: 110, y: -40), isCamera: false, stop: CGPoint(x: 110, y: 20), facing: 0)
    ]
    private let start = CGPoint(x: 40, y: 125)

    var body: some View {
        Looping(phases: [0, 1, 2, 3], animates: animates) { phase in
            ZStack {
                SubjectCard()
                    .scaleEffect(0.8)
                    .offset(y: -95)
                ForEach(items.indices, id: \.self) { index in
                    item(items[index], captured: phase > index)
                        .offset(x: items[index].position.x, y: items[index].position.y)
                }
                phone(at: phase)
            }
        }
    }

    private func phone(at phase: Int) -> some View {
        let target = phase == 0 ? nil : items[phase - 1]
        let position = target?.stop ?? start
        return ZStack {
            ViewCone()
                .fill(DesignTokens.accentPrimary.opacity(0.15))
                .frame(width: 50, height: 36)
                .offset(x: 25)
                .rotationEffect(.degrees(-90))
            PhoneShape()
                .scaleEffect(0.8)
        }
        .rotationEffect(.degrees(target?.facing ?? -20))
        .offset(x: position.x, y: position.y)
    }

    private func item(_ item: Item, captured: Bool) -> some View {
        let color = captured ? DesignTokens.detectedGreen : DesignTokens.diagramStroke
        return Group {
            if item.isCamera {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(color, lineWidth: 2)
                    .frame(width: 30, height: 22)
            } else {
                Trapezoid()
                    .stroke(color, lineWidth: 2)
                    .frame(width: 30, height: 20)
            }
        }
        .overlay(alignment: .top) {
            if captured {
                Image(systemName: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.detectedGreen)
                    .offset(y: -18)
            }
        }
    }
}

// MARK: - 4. Tap Finish Scan

private struct FinishDrawing: View {
    let animates: Bool
    private let rows = ["Subject", "Camera", "Light"]

    var body: some View {
        Looping(phases: [0, 1, 2, 3, 4], animates: animates) { phase in
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows.indices, id: \.self) { index in
                        HStack(spacing: 8) {
                            Image(systemName: phase > index ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(phase > index ? DesignTokens.detectedGreen : DesignTokens.textSecondary)
                            Text(rows[index])
                                .font(.footnote)
                                .foregroundStyle(DesignTokens.textPrimary)
                        }
                    }
                }
                .padding(12)
                .background(DesignTokens.diagramSubjectFill, in: .rect(cornerRadius: 12))

                HStack(spacing: 6) {
                    Text("Finish Scan")
                    Image(systemName: "checkmark")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DesignTokens.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(DesignTokens.diagramSubjectFill, in: .capsule)
                .overlay(Capsule().strokeBorder(phase >= 4 ? DesignTokens.detectedGreen : DesignTokens.diagramSubjectBorder,
                                                lineWidth: 2))
                .scaleEffect(phase >= 4 ? 1.06 : 1)
            }
        }
    }
}
