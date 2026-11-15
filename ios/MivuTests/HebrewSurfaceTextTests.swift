import Foundation
import Testing
@testable import Mivu

/// Text shown outside the app (notifications, Siri) resolves to Hebrew from the built bundle.
struct HebrewSurfaceTextTests {
    @Test func notificationAndSiriTextHasHebrew() throws {
        let hebrew = try #require(Bundle.main.path(forResource: "he", ofType: "lproj").flatMap(Bundle.init(path:)))
        let keys = ["Good morning", "Log your weight or breakfast.", "Coach", "The Coach needs a quick answer.",
                    "Your message is saved. Open Mivu for the Coach's reply.", "%@ logged", "%@ is ready to review", "Tap to review",
                    "Couldn't recognize your meal", "Sent to the Coach.", "Saved. Open Mivu to connect the Coach.",
                    "Open Mivu to finish setup first.", "I couldn't save that. Please try again.", "Tell Coach", "Open Coach"]
        for key in keys {
            let value = hebrew.localizedString(forKey: key, value: "", table: nil)
            #expect(value.unicodeScalars.contains { (0x05D0...0x05EA).contains($0.value) }, "\(key) → \(value)")
        }
    }
}
