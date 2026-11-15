import Foundation
import Testing
@testable import Mivu

struct CoachVoiceLanguagesTests {
    private func codes(_ locales: [Locale]) -> [String?] { locales.map { $0.language.languageCode?.identifier } }

    @Test func appLanguageComesFirstWhenSupported() {
        let options = CoachVoiceLanguages.options(app: Locale(identifier: "he"), keyboards: ["en-US", "he-IL"]) { _ in true }
        #expect(codes(options) == ["he", "en"])
    }

    @Test func unsupportedKeyboardsAreNotOffered() {
        let options = CoachVoiceLanguages.options(app: Locale(identifier: "en-US"), keyboards: ["ar", "emoji", "he-IL"]) { $0.language.languageCode?.identifier != "ar" && $0.identifier != "emoji" }
        #expect(codes(options) == ["en", "he"])
    }

    @Test func nothingSupportedFallsBackToEnglish() {
        #expect(CoachVoiceLanguages.options(app: Locale(identifier: "he"), keyboards: ["he-IL"]) { _ in false }.map(\.identifier) == ["en-US"])
    }

    @Test func namesUseTheirOwnLanguage() {
        #expect(CoachVoiceLanguages.name(Locale(identifier: "he-IL")) == "עברית")
        #expect(CoachVoiceLanguages.name(Locale(identifier: "en-US")) == "English")
    }
}
