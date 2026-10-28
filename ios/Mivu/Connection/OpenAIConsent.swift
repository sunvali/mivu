import SwiftUI

enum MivuLinks {
    static let privacyPolicy = URL(string: "https://mivuapp.com/privacy")!
    static let chatGPTUsage = URL(string: "https://chatgpt.com/settings/usage")!

    /// App Review 1.2: a way to report an AI reply. The person sends the email themselves.
    static func reportReply(_ reply: String) -> URL {
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = "support@mivuapp.com"
        parts.queryItems = [
            URLQueryItem(name: "subject", value: "Report a Coach reply"),
            URLQueryItem(name: "body", value: "What was wrong with this reply?\n\n\n---\n\(reply)")
        ]
        return parts.url!
    }
}

extension View {
    /// App Review 5.1.2(i): name OpenAI and the data before anything is shared with it.
    func openAIConsent(isPresented: Binding<Bool>, connection: ChatGPTConnection, onAgree: @escaping () -> Void) -> some View {
        alert("Share with OpenAI?", isPresented: isPresented) {
            Button("Agree and Continue") { connection.recordSharingConsent(); onAgree() }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("To estimate nutrition and answer Coach, Mivu sends OpenAI, through your ChatGPT account, what you record: meals, photos, messages, weights, workouts, goals and profile details. If you add a USDA key, food searches go to USDA FoodData Central. Your diary stays on this iPhone, and you can disconnect any time in Settings.")
        }
    }
}
