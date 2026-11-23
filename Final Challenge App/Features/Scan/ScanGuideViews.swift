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

#Preview("Chips and Finish") {
    VStack(spacing: 16) {
        ScanStatusChips(hasFloor: true, hasSubject: true, hasCamera: false, hasLight: false)
        ScanFinishButton(isEnabled: true) {}
        ScanFinishButton(isEnabled: false) {}
    }
    .padding()
    .background(.gray)
    .preferredColorScheme(.dark)
}
