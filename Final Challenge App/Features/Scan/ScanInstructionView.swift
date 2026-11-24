//
//  ScanInstructionView.swift
//  Final Challenge App
//
//  The scan screen's one instruction (layout A, 24 Nov 2026): always at the same height, in the upper third, so the
//  eye never hunts for it and the middle of the screen, where the item being aimed at is, stays clear. Steps and
//  "done" lines are plain white text; when the user is held up (a problem, or a tap that set nothing), the camera dims
//  and an icon sits above the same text.
//  Full screen; taps always go through to the camera; VoiceOver reads each new line.
//

import SwiftUI

struct ScanInstructionView: View {
    let instruction: ScanInstruction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How dark the camera gets behind a blocking line (about what Apple's coaching screen uses).
    static let dim = 0.6
    /// How dark the soft glow behind a step line is at its middle.
    static let glow = 0.45
    /// Where every line sits, as a share of the screen's height from the top.
    static let lineHeight = 0.38
    /// The icon above a blocking line: its box, and the gap between it and the line.
    static let iconHeight: CGFloat = 56
    static let iconGap: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if instruction.isBlocking {
                    Color.black.opacity(Self.dim)
                        .transition(.opacity)
                }
                Group {
                    if instruction.isBlocking { blocking } else { plain }
                }
                .frame(maxWidth: geometry.size.width * 0.8)
                .position(x: geometry.size.width / 2, y: geometry.size.height * Self.lineHeight)
            }
            .id(instruction)
            .transition(.opacity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .onChange(of: instruction, initial: true) {
            let spoken = [instruction.main, instruction.detail].compactMap { $0 }.joined(separator: ". ")
            AccessibilityNotification.Announcement(spoken).post()
        }
    }

    /// The line and small line over the dimmed camera, with the icon above them, so the text stays where a step's is.
    private var blocking: some View {
        VStack(spacing: 4) {
            Text(instruction.main)
                .font(.title3.weight(.semibold))
            if let detail = instruction.detail {
                Text(detail)
                    .font(.subheadline)
                    .opacity(0.85)
            }
        }
        .overlay(alignment: .top) {
            // A fixed box moved up by its own height plus the gap, so the icon always ends above the line, whatever
            // the symbol's shape.
            if let symbol = instruction.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 44, weight: .regular))
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                    .frame(height: Self.iconHeight)
                    .offset(y: -(Self.iconHeight + Self.iconGap))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
    }

    /// The line and small line as white text over a soft dark glow (no box: a blurred oval that fades out at its
    /// edges), with two shadows so the letters keep crisp edges, so they read over a white wall or a bright softbox.
    private var plain: some View {
        VStack(spacing: 4) {
            Text(instruction.main)
                .font(.title2.weight(.bold))
            if let detail = instruction.detail {
                Text(detail)
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
        .shadow(color: .black.opacity(0.6), radius: 6)
        .background {
            Ellipse()
                .fill(.black.opacity(Self.glow))
                .padding(-28)
                .blur(radius: 24)
                .accessibilityHidden(true)
        }
    }
}

#Preview("Step") {
    ScanInstructionView(instruction: ScanInstruction(main: "Point at the floor",
                                                     detail: "Heights are measured from it", style: .step))
        .background(.gray)
}

#Preview("Blocking") {
    ScanInstructionView(instruction: ScanInstruction(main: "More light needed",
                                                     detail: "Turn on more lights in the room", style: .problem,
                                                     symbol: "lightbulb.max.fill"))
        .background(.gray)
}
