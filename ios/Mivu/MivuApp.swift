import SwiftUI

@main
struct MivuApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: MivuAppDelegate
    var body: some Scene {
        WindowGroup {
            root
                .environment(\.locale, Locale(identifier: "en"))
                .environment(\.layoutDirection, .leftToRight)
        }
    }

    @ViewBuilder private var root: some View {
        #if DEBUG
        if CommandLine.arguments.contains("-PipRigPreview") { PipRigPreview() } else { diary }
        #else
        diary
        #endif
    }

    @ViewBuilder private var diary: some View {
        if DiaryLaunch.shouldLaunchDiary { DiaryRootView() }
        else { Color.clear }
    }
}
