import AppIntents

// Compiled into the app and the widget extension; openAppWhenRun makes the system perform them in the app.
struct LogFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Snap It"
    static let description = IntentDescription("Opens the camera to photograph a meal and log it.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        QuickLogRequest.shared.pending = true
        #endif
        return .result()
    }
}

struct OpenCoachIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Coach"
    static let description = IntentDescription("Opens Mivu Coach, ready for a question.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        QuickLogRequest.shared.openCoach = true
        #endif
        return .result()
    }
}
