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
        connection.accountState == .planPermissionMissing ? "Enable ChatGPT plan usage"
            : connection.activeRegistrationID == nil ? "Continue with ChatGPT" : "Reauthorize ChatGPT"
    }

    private func connect() { Task { await connection.connect() } }
}
