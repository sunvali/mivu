import SwiftUI
import WidgetKit

/// Control Center, Lock Screen and Action button entry to the Log Food camera.
struct LogFoodControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.yakov103.mivu.log-food-control") {
            ControlWidgetButton(action: LogFoodIntent()) { Label("Log Food", systemImage: "camera") }
        }
        .displayName("Log Food")
        .description("Photograph a meal and log it in Mivu.")
    }
}
