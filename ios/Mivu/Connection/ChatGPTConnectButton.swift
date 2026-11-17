import SwiftUI

/// The one way to start a ChatGPT connection from any screen: sharing consent first, then sign-in.
struct ChatGPTConnectButton: View {
    let connection: ChatGPTConnection
    var title: String?
    @State private var askConsent = false

    var body: some View {
        Button(title ?? defaultTitle) {
            if connection.sharingConsented { connect() } else { askConsent = true }
        }
        .disabled(connection.isConnecting || connection.isDisconnecting)
        .accessibilityIdentifier("connectChatGPT")
        .openAIConsent(isPresented: $askConsent, connection: connection, onAgree: connect)
    }

    private var defaultTitle: String {
        connection.accountState == .planPermissionMissing ? String(localized: "Enable ChatGPT plan usage")
            : connection.activeRegistrationID == nil ? String(localized: "Continue with ChatGPT") : String(localized: "Reauthorize ChatGPT")
    }

    private func connect() { Task { await connection.connect() } }
}
