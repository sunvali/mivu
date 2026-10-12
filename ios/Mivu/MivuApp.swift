import SwiftUI

@main
struct MivuApp: App {
    var body: some Scene {
        WindowGroup {
            Group {
                if DiaryLaunch.shouldLaunchDiary { DiaryRootView() }
                else { Color.clear }
            }
            .environment(\.locale, Locale(identifier: "en"))
            .environment(\.layoutDirection, .leftToRight)
        }
    }
}
