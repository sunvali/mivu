import SwiftUI
import WidgetKit

/// Control Center, Lock Screen and Action button entry to the Snap It camera.
struct LogFoodControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.yakov103.mivu.log-food-control") {
            ControlWidgetButton(action: LogFoodIntent()) { Label("Snap It", systemImage: "camera") }
        }
        .displayName("Snap It")
        .description("Photograph a meal and log it in Mivu.")
    }
}
