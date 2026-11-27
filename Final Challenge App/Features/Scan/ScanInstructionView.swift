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
    static let topGap: CGFloat = 12
    static let iconGap: CGFloat = 14
    static let blockingHeight = 0.5

    var body: some View {
        ZStack(alignment: .top) {
            if instruction.isBlocking {
                Color.black.opacity(Self.dim)
                    .ignoresSafeArea()
                    .transition(.opacity)
                // Problem lines sit a little above the middle of the screen.
                GeometryReader { geometry in
                    blocking
                        .padding(.horizontal, 40)
                        .position(x: geometry.size.width / 2, y: geometry.size.height * Self.blockingHeight)
                }
                .ignoresSafeArea()
            } else {
                // Step lines sit at the top, just under the X.
                plain
                    .padding(.horizontal, 40)
                    .padding(.top, Self.topGap)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .id(instruction)
        .transition(.opacity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .onChange(of: instruction, initial: true) {
            let spoken = [instruction.main, instruction.detail].compactMap { $0 }.joined(separator: ". ")
            AccessibilityNotification.Announcement(spoken).post()
        }
    }

    /// The line and small line over the dimmed camera, with the icon above them, so the text stays where a step's is.
    private var blocking: some View {
        VStack(spacing: Self.iconGap) {
            if let symbol = instruction.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 44, weight: .regular))
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 4) {
                Text(instruction.main)
                    .font(.title3.weight(.semibold))
                if let detail = instruction.detail {
                    Text(detail)
                        .font(.subheadline)
                        .opacity(0.85)
                }
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
    }

    /// The line and small line as white text over a soft dark glow (no box: a blurred oval that fades out at its
    /// edges), with two shadows so the letters keep crisp edges, so they read over a white wall or a bright softbox.
    private var plain: some View {
        VStack(spacing: 2) {
            Text(instruction.main)
                .font(.headline)
            if let detail = instruction.detail {
                Text(detail)
                    .font(.subheadline)
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
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
