import SwiftUI
import WidgetKit

/// Control Center, Lock Screen and Action button entry to the Snap It camera.
struct LogFoodControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: LogFoodIntent.controlKind) {
            ControlWidgetButton(action: LogFoodIntent()) { Label("Snap It", image: "pip.head") }
        }
        .displayName("Snap It")
        .description("Photograph a meal and log it in Mivu.")
    }
}
