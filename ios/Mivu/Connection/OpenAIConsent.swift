import SwiftUI

enum MivuLinks {
    // shortcut: placeholder until the owner supplies the hosted policy; must be replaced before submission.
    static let privacyPolicy = URL(string: "https://example.com/mivu/privacy")!
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
