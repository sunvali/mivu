import SwiftUI

@main
struct MivuApp: App {
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--proof-hebrew") { UserDefaults.standard.set("he", forKey: "appLanguage") }
        if arguments.contains("--proof-english") { UserDefaults.standard.set("en", forKey: "appLanguage") }
    }

    var body: some Scene {
        WindowGroup {
            ConnectionProofView()
        }
    }
}
