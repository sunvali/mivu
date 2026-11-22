import SwiftUI

/// The one way to start a ChatGPT connection from any screen: sharing consent first, then sign-in.
struct ChatGPTConnectButton: View {
    let connection: ChatGPTConnection
    var title: String?
    @State private var askConsent = false

    var body: some View {
        Button(buttonTitle) {
            if connection.sharingConsented { connect() } else { askConsent = true }
        }
        .disabled(connection.isConnecting || connection.isDisconnecting)
        .accessibilityIdentifier("connectChatGPT")
        .openAIConsent(isPresented: $askConsent, connection: connection, onAgree: connect)
    }

    private var buttonTitle: String {
        if connection.accountState == .planPermissionMissing { return String(localized: "Enable ChatGPT plan usage") }
        return title ?? (connection.activeRegistrationID == nil ? String(localized: "Continue with ChatGPT") : String(localized: "Reauthorize ChatGPT"))
    }

    private func connect() { Task { await connection.connect() } }
}

struct ChatGPTPlanHint: View {
    let connection: ChatGPTConnection

    var body: some View {
        if connection.activeRegistrationID == nil || connection.accountState == .planPermissionMissing {
            VStack(alignment: .leading, spacing: 4) {
                if connection.accountState == .planPermissionMissing {
                    Text(LocalizedStringKey(ConnectionNotice.permission.rawValue))
                }
                Text("Requires ChatGPT Go or higher.")
            }
            .font(.footnote)
            .foregroundStyle(Color.diarySecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
