import SwiftUI

@main
struct MivuApp: App {
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--proof-hebrew") { DiaryLaunch.defaults.set("he", forKey: "appLanguage") }
        if arguments.contains("--proof-english") { DiaryLaunch.defaults.set("en", forKey: "appLanguage") }
    }
    var body: some Scene { WindowGroup { DiaryRootView() } }
}
