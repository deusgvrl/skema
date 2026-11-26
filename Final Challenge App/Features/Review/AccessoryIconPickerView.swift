//
//  AccessoryIconPickerView.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 26/11/26.
//

import SwiftUI

struct AccessoryIconPickerView: View {
    @Binding var selectedType: AccessoryType
    var isReadOnly: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AccessoryType.allCases) { accType in
                let isSelected = selectedType == accType
                let iconName = EquipmentCategory.accessory.imageName(
                    isSelected: isSelected,
                    accessoryType: accType
                )

                Button {
                    guard !isReadOnly else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedType = accType
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(iconName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 54, height: 54)

                        Text(accType.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(isSelected ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? DesignTokens.accentPrimary : Color.white.opacity(0.08),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(isReadOnly)
            }
        }
        .padding(.vertical, 4)
    }
}
