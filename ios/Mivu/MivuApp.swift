import SwiftUI

@main
struct MivuApp: App {
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if DiaryLaunch.isCoachScrollSpike { CoachScrollSpikeView() }
                else if DiaryLaunch.shouldLaunchDiary { DiaryRootView() }
                else { Color.clear }
                #else
                if DiaryLaunch.shouldLaunchDiary { DiaryRootView() }
                else { Color.clear }
                #endif
            }
            .environment(\.locale, Locale(identifier: "en"))
            .environment(\.layoutDirection, .leftToRight)
        }
    }
}
