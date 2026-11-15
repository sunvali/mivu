import Speech
import UIKit

/// The languages the Coach microphone can listen in: the app language first, then the person's keyboard languages.
enum CoachVoiceLanguages {
    /// One locale per language, kept only when speech can transcribe it; English when nothing is supported.
    static func options(app: Locale, keyboards: [String], supported: (Locale) -> Bool) -> [Locale] {
        var seen = Set<String>()
        let options = ([app] + keyboards.map(Locale.init(identifier:))).filter { locale in
            guard let code = locale.language.languageCode?.identifier, supported(locale) else { return false }
            return seen.insert(code).inserted
        }
        return options.isEmpty ? [Locale(identifier: "en-US")] : options
    }

    /// The app language; English keeps the US English it always used.
    static var app: Locale {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale(identifier: code == "en" ? "en-US" : code)
    }

    /// Asks speech once per candidate language, so the menu only offers what can be transcribed here.
    @MainActor static func available() async -> [Locale] {
        let app = app
        let keyboards = UITextInputMode.activeInputModes.compactMap(\.primaryLanguage)
        var supported = Set<String>()
        for locale in [app] + keyboards.map(Locale.init(identifier:)) where !supported.contains(locale.identifier) {
            let transcriber = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
            let dictation = await DictationTranscriber.supportedLocale(equivalentTo: locale)
            if transcriber != nil || dictation != nil { supported.insert(locale.identifier) }
        }
        return options(app: app, keyboards: keyboards) { supported.contains($0.identifier) }
    }

    /// "עברית", "English": each language in its own words.
    static func name(_ locale: Locale) -> String {
        let code = locale.language.languageCode?.identifier ?? locale.identifier
        return Locale(identifier: code).localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
    }
}
