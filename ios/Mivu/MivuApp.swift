import SwiftUI

@main
struct MivuApp: App {
    var body: some Scene {
        WindowGroup {
            DiaryRootView()
                .environment(\.locale, Locale(identifier: "en"))
                .environment(\.layoutDirection, .leftToRight)
        }
    }
}
