//
//  ScanGuideSheet.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 08/11/26.
//
//  "Before You Scan": a 4-step tutorial with a small animation per step. Restyled from Sketch R02;
//  the steps replace R02's "walk around the set" copy, which made users circle the whole room.
//

import SwiftUI

struct ScanGuideSheet: View {
    let onStartScanning: () -> Void
    let onDontShowAgain: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step: ScanTutorialStep = .tapSubject

    var body: some View {
        VStack(spacing: 0) {
            header

            TabView(selection: $step) {
                ForEach(ScanTutorialStep.allCases) { step in
                    ScanTutorialPage(step: step)
                        .tag(step)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            PageDots(current: step)
                .padding(.vertical, 12)

            buttons
        }
        .presentationBackground(DesignTokens.sheetBackground)
    }

    private var header: some View {
        HStack {
            Text("Before You Scan")
                .font(.title3.bold())
                .foregroundStyle(DesignTokens.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Close", systemImage: "xmark") {
                dismiss()
            }
            .labelStyle(.iconOnly)
            .font(.body.weight(.medium))
            .foregroundStyle(DesignTokens.textPrimary)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
        }
        .padding(.leading, 24)
        .padding(.trailing, 16)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    private var buttons: some View {
        VStack(spacing: 14) {
            Button {
                if let next = step.next {
                    withAnimation { step = next }
                } else {
                    onStartScanning()
                }
            } label: {
                Text(step.primaryButtonTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(DesignTokens.accentPrimary, in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)

            Button("Don’t Show Again", action: onDontShowAgain)
                .font(.subheadline)
                .foregroundStyle(DesignTokens.accentText)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
}

/// One step: the drawing, then its title and one sentence.
private struct ScanTutorialPage: View {
    let step: ScanTutorialStep

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScanTutorialIllustration(step: step)
                    .frame(height: 320)

                VStack(spacing: 6) {
                    Text(step.title)
                        .font(.title3.bold())
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text(step.message)
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(step.positionLabel). \(step.title). \(step.message)")
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct PageDots: View {
    let current: ScanTutorialStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ScanTutorialStep.allCases) { step in
                Capsule()
                    .fill(step == current ? DesignTokens.textPrimary : DesignTokens.textSecondary.opacity(0.4))
                    .frame(width: step == current ? 18 : 7, height: 7)
            }
        }
        .animation(.default, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(current.positionLabel)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ScanGuideSheet(onStartScanning: {}, onDontShowAgain: {})
                .presentationDetents([.large])
        }
}
