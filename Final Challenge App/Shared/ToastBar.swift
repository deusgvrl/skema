import SwiftUI

/// The bottom toast of the Setups list. SwiftUI has no built-in toast,
/// so "Setup deleted" and "Setup saved" share this one.
struct ToastBar: View {
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(message)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .bold()
            }
        }
        .padding()
        .background(.regularMaterial, in: .capsule)
        .padding(.horizontal)
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
