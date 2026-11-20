import SwiftUI

/// A white glass toast at the bottom of a screen (Sketch UT Review A-S08, A-S10, A-S11):
/// an icon, a short message and, optionally, a red action after a divider ("Undo").
struct ToastBar: View {
    let systemImage: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(DesignTokens.textSecondary)
                .accessibilityHidden(true)
            Text(message)
                .foregroundStyle(DesignTokens.textPrimary)
            if let actionTitle, let action {
                Divider()
                    .frame(height: 20)
                Button(actionTitle, action: action)
                    .fontWeight(.semibold)
                    .foregroundStyle(DesignTokens.accentText)
            }
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 18)
        .frame(minHeight: 48)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

private struct SetupSavedActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Called when a setup is saved, so the Setups list can show its "Setup saved" toast.
    var setupSavedAction: (() -> Void)? {
        get { self[SetupSavedActionKey.self] }
        set { self[SetupSavedActionKey.self] = newValue }
    }
}
