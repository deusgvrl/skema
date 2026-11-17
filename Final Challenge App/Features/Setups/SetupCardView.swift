//
//  SetupCardView.swift
//  Final Challenge App
//
//  Card in a month's horizontal carousel for the "Recent" grouping (Sketch R01 / Light · R01).
//  The current month uses the larger, prominent size.
//

import SwiftUI

struct SetupCardView: View {
    let setup: Setup
    var isProminent = false

    private var cardWidth: CGFloat { isProminent ? 236 : 150 }
    private var coverHeight: CGFloat { isProminent ? 166 : 100 }

    private var lightsCount: Int {
        setup.nodes.filter { $0.category == .light }.count
    }

    private var subtitle: String {
        setup.client.isEmpty ? "\(lightsCount) lights" : "\(setup.client) · \(lightsCount) lights"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            coverArt
                .frame(width: cardWidth - 16, height: coverHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(setup.setupName)
                    .font(isProminent ? .headline : .subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }
            .padding(.top, 8)
            .padding(.horizontal, 6)
        }
        .padding(8)
        .frame(width: cardWidth, alignment: .leading)
        .glassCard()
    }

    private var coverArt: some View {
        CoverImageView(reference: setup.coverImage, pointSize: cardWidth) {
            ZStack {
                Color(uiColor: .systemGray5)
                Image(systemName: "camera.aperture")
                    .font(isProminent ? .largeTitle : .title)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack {
        SetupCardView(setup: Setup(setupName: "Skincare / soft daylight", client: "Aesop"), isProminent: true)
        SetupCardView(setup: Setup(setupName: "Bathtub / side light", client: "APAISER"))
    }
    .padding()
}
