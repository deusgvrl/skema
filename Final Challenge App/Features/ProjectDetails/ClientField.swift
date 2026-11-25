//
//  ClientField.swift
//  Skema Photo
//
//  The Client row's value: type a new client, or pick one used in a saved setup.
//

import SwiftUI

struct ClientField: View {
    @Binding var client: String
    /// Clients of saved setups, A to Z. Empty hides the menu, so a first-time user only sees the text field.
    let savedClients: [String]

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            TextField("Client", text: $client, prompt: Text("e.g. Bloom Skincare"))
                .focused($isFocused)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)

            if !savedClients.isEmpty {
                clientMenu
            }
        }
    }

    private var clientMenu: some View {
        Menu {
            Section("Saved Clients") {
                ForEach(savedClients, id: \.self) { name in
                    Toggle(name, isOn: selection(of: name))
                }
            }
            Button("New Client", systemImage: "plus") {
                client = ""
                isFocused = true
            }
        } label: {
            Image(systemName: "chevron.up.chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(width: 44, height: 44, alignment: .trailing)
                .contentShape(.rect)
        }
        // A 44 pt tap area without making the row taller than the others.
        .padding(.vertical, -11)
        .accessibilityLabel("Choose a saved client")
    }

    /// On for the current client; tapping any name picks it. "aesop " and "Aesop" are the same client, as in By Client.
    private func selection(of name: String) -> Binding<Bool> {
        Binding {
            SetupSections.clientKey(for: name) == SetupSections.clientKey(for: client)
        } set: { _ in
            isFocused = false
            client = name
        }
    }
}
