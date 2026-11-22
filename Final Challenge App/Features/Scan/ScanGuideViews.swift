//
//  ScanGuideViews.swift
//  Final Challenge App
//
//  The guided scan's controls over the camera (Sketch UT Review T01–T10): the coaching panel, the hint pill shown
//  instead of it after the first scan, the Floor · Subject · Camera · Light chips and Finish Scan.
//  The camera screens are always dark, so these use fixed light-on-dark colours.
//

import SwiftUI

/// The scan screen's fixed colours.
enum ScanPalette {
    /// The tags, boxes and ticks (#30D158, Sketch).
    static let green = Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)
    /// Text on the green tags: black, because white on this green is under 2:1.
    static let onGreen = Color.black
    /// Darkens the glass so white text stays readable over a bright set.
    static let glassTint = Color.black.opacity(0.35)
}

/// "STEP n OF 5", the step's title and message, five progress bars and Skip; for a moment after a tap,
/// "STEP n OF 5 · DONE" with a green tick instead (Sketch T01–T09).
struct ScanCoachingPanel: View {
    let step: ScanStep
    /// The step whose tap just landed; shows the done state while set.
    let completed: ScanStep?
    let onSkip: () -> Void

    private var shownStep: ScanStep { completed ?? step }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(completed == nil ? step.positionLabel : "\(shownStep.positionLabel) · DONE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(completed == nil ? Color.white.opacity(0.75) : ScanPalette.green)
                Spacer()
                Button("Skip", action: onSkip)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .accessibilityHint("Hides these tips. Tap ? to see them again.")
            }
            if let completed, let done = completed.doneTitle {
                Label(done, systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.palette)
                    .labelStyle(DoneLabelStyle())
            } else {
                Text(step.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text(step.message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            progress
                .padding(.top, 6)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(ScanPalette.glassTint), in: .rect(cornerRadius: 24))
        .animation(.default, value: completed)
        .accessibilityElement(children: .contain)
    }

    /// Done steps green, the current one white, the rest dim.
    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(ScanStep.allCases, id: \.self) { item in
                Capsule()
                    .fill(color(for: item))
                    .frame(height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(for item: ScanStep) -> Color {
        if let completed, item.rawValue <= completed.rawValue { return ScanPalette.green }
        if item.rawValue < step.rawValue { return ScanPalette.green }
        if item == step { return .white }
        return .white.opacity(0.25)
    }
}

/// The tick in green on a white-on-green circle, then the title.
private struct DoneLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .foregroundStyle(.white, ScanPalette.green)
            configuration.title
        }
    }
}

/// The short line shown instead of the panel once the tutorial is done (Sketch T10): the next tap, or a tick for a
/// moment after one lands.
struct ScanHintPill: View {
    let step: ScanStep
    let completed: ScanStep?

    var body: some View {
        Group {
            if let done = completed?.doneTitle {
                Label(done, systemImage: "checkmark")
                    .foregroundStyle(ScanPalette.green)
            } else {
                Text(step.hint)
                    .foregroundStyle(.white)
            }
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .glassEffect(.regular.tint(ScanPalette.glassTint), in: .capsule)
        .animation(.default, value: completed)
    }
}

/// Floor · Subject · Camera · Light, each with a dot that turns green once it is tapped.
struct ScanStatusChips: View {
    let hasFloor: Bool
    let hasSubject: Bool
    let hasCamera: Bool
    let hasLight: Bool

    var body: some View {
        HStack(spacing: 8) {
            chip("Floor", isDone: hasFloor)
            chip("Subject", isDone: hasSubject)
            chip("Camera", isDone: hasCamera)
            chip("Light", isDone: hasLight)
        }
    }

    private func chip(_ title: String, isDone: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isDone ? ScanPalette.green : Color.white.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(title)
                .font(.footnote)
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular.tint(ScanPalette.glassTint), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isDone ? "Done" : "Not yet")
    }
}

/// Finish Scan: dim glass until it can finish, then white with a ring around it (Sketch T09).
struct ScanFinishButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Finish Scan", systemImage: "checkmark")
                .labelStyle(TrailingIconLabelStyle())
                .font(.title3)
                .foregroundStyle(isEnabled ? Color.black : Color.white.opacity(0.45))
                .frame(width: 210, height: 56)
                .background {
                    if isEnabled {
                        Capsule().fill(.white)
                    }
                }
                .glassEffect(isEnabled ? .identity : .regular.tint(ScanPalette.glassTint), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .padding(8)
        .overlay {
            if isEnabled {
                Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 2)
            }
        }
        .disabled(!isEnabled)
        .animation(.default, value: isEnabled)
    }
}

/// "Finish Scan ✓": the title, then the icon.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.title
            configuration.icon.accessibilityHidden(true)
        }
    }
}

#Preview("Coaching panel") {
    VStack(spacing: 16) {
        ScanCoachingPanel(step: .floor, completed: nil, onSkip: {})
        ScanCoachingPanel(step: .camera, completed: .subject, onSkip: {})
        ScanHintPill(step: .floor, completed: nil)
        ScanStatusChips(hasFloor: true, hasSubject: true, hasCamera: false, hasLight: false)
        ScanFinishButton(isEnabled: true) {}
        ScanFinishButton(isEnabled: false) {}
    }
    .padding()
    .background(.gray)
    .preferredColorScheme(.dark)
}
