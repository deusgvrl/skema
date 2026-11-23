//
//  ScanGuideViews.swift
//  Final Challenge App
//
//  The guided scan's controls over the camera (Sketch UT Review T01–T10): the Floor · Subject · Camera · Light chips
//  and Finish Scan. The instruction in the middle of the screen is `ScanInstructionView`.
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

/// One of the progress chips above Finish Scan, in step order.
enum ScanChip: Int, CaseIterable {
    case floor
    case subject
    case camera
    case lights

    /// Done (green, with a checkmark), now (white) or still to do (glass): never colour alone (Apple HIG, Color).
    enum State: Equatable {
        case done
        case now
        case todo
    }

    /// The chips before the current step are done, the current step's is now, the rest are still to do.
    func state(at step: ScanStep) -> State {
        if rawValue < step.rawValue { return .done }
        return rawValue == step.rawValue ? .now : .todo
    }

    /// "Floor", "Subject", "Camera"; the lights chip counts the lights once there are any ("2 Lights").
    func title(lights: Int) -> String {
        switch self {
        case .floor: "Floor"
        case .subject: "Subject"
        case .camera: "Camera"
        case .lights: lights == 0 ? "Lights" : "\(lights) Light\(lights == 1 ? "" : "s")"
        }
    }
}

/// Floor · Subject · Camera · Lights: the whole chip turns green with a checkmark once its step is done, and the
/// current step's chip is white, so the photographer sees at a glance where the scan is.
struct ScanStatusChips: View {
    let step: ScanStep
    let lights: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ScanChip.allCases, id: \.self) { chip($0) }
        }
    }

    private func chip(_ chip: ScanChip) -> some View {
        let state = chip.state(at: step)
        let title = chip.title(lights: lights)
        return HStack(spacing: 4) {
            if state == .done {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
            }
            Text(title)
                .font(.footnote.weight(state == .todo ? .regular : .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(state == .todo ? Color.white : ScanPalette.onGreen)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            switch state {
            case .done: Capsule().fill(ScanPalette.green)
            case .now: Capsule().fill(.white)
            case .todo: EmptyView()
            }
        }
        .glassEffect(state == .todo ? .regular.tint(ScanPalette.glassTint) : .identity, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(state == .done ? "Done" : state == .now ? "Now" : "Not yet")
        .animation(.default, value: state)
    }
}

/// Finish Scan: dim glass until it can finish, then white with a ring around it (Sketch T09). Always tappable: before
/// the scan can finish, a tap says what to add first (HIG Feedback: say why a command can't be carried out).
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
        .accessibilityHint(isEnabled ? "" : "Says what to add first")
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

#Preview("Chips and Finish") {
    VStack(spacing: 16) {
        ScanStatusChips(step: .camera, lights: 0)
        ScanStatusChips(step: .finish, lights: 2)
        ScanFinishButton(isEnabled: true) {}
        ScanFinishButton(isEnabled: false) {}
    }
    .padding()
    .background(.gray)
    .preferredColorScheme(.dark)
}
