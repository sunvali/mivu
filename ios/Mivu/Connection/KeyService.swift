import Foundation
import Security

/// An AI service a person powers with their own credential, next to ChatGPT sign-in.
enum KeyService: String, CaseIterable, Sendable {
    case claude, openAI, gemini, openRouter

    var name: String {
        switch self {
        case .claude: "Claude"
        case .openAI: "OpenAI"
        case .gemini: "Gemini"
        case .openRouter: "OpenRouter"
        }
    }

    /// Who receives the data; named in the consent prompt.
    var company: String {
        switch self {
        case .claude: "Anthropic"
        case .openAI: "OpenAI"
        case .gemini: "Google"
        case .openRouter: "OpenRouter"
        }
    }

    var caption: String {
        switch self {
        case .claude, .openAI: "Paste a key · pay per use"
        case .gemini: "Paste a key · has a free tier"
        case .openRouter: "Sign in · one account, many models"
        }
    }

    /// What the "Get a key" page is called, so the link says where it leads.
    var keyPageName: String {
        switch self {
        case .claude: "Claude Console"
        case .openAI: "OpenAI Platform"
        case .gemini: "Google AI Studio"
        case .openRouter: "OpenRouter"
        }
    }

    var keyPage: URL {
        let page = switch self {
        case .claude: "https://platform.claude.com/settings/keys"
        case .openAI: "https://platform.openai.com/api-keys"
        case .gemini: "https://aistudio.google.com/apikey"
        case .openRouter: "https://openrouter.ai/settings/keys"
        }
        return URL(string: page)!
    }

    var usagePage: URL {
        let page = switch self {
        case .claude: "https://platform.claude.com/usage"
        case .openAI: "https://platform.openai.com/usage"
        case .gemini: "https://aistudio.google.com/usage"
        case .openRouter: "https://openrouter.ai/activity"
        }
        return URL(string: page)!
    }

    // Model ids looked up on 2026-11-14: each service's cheapest chat model that reads photos and calls tools.
    var defaultModel: String {
        switch self {
        case .claude: "claude-haiku-5-5"
        case .openAI: "gpt-6-luna"
        case .gemini: "gemini-3.5-flash-lite"
        case .openRouter: "anthropic/claude-haiku-5.5"
        }
    }

    /// OpenRouter lists several hundred models; the picker offers these.
    var shortlist: [AvailableModel] {
        guard self == .openRouter else { return [] }
        return [("anthropic/claude-haiku-5.5", "Claude Haiku 5.5"), ("openai/gpt-6-luna", "GPT-6 Luna"),
                ("google/gemini-3.8-flash", "Gemini 3.8 Flash"), ("anthropic/claude-sonnet-5.5", "Claude Sonnet 5.5"),
                ("openai/gpt-6.1-terra", "GPT-6.1 Terra"), ("anthropic/claude-opus-5.5", "Claude Opus 5.5")]
            .map { AvailableModel(slug: $0.0, displayName: $0.1) }
    }

    /// OpenAI consent is one decision whether the person signs in with ChatGPT or pastes an OpenAI key.
    var consentKey: String { self == .openAI ? "openAISharingConsent" : rawValue + "SharingConsent" }

    var connectsBySignIn: Bool { self == .openRouter }

    /// Whether a listed model is a chat model worth offering; the services also list embedding, speech and image models.
    func lists(_ modelID: String) -> Bool {
        func none(_ words: [String]) -> Bool { !words.contains { modelID.contains($0) } }
        return switch self {
        case .claude: modelID.hasPrefix("claude-")
        case .openAI: modelID.hasPrefix("gpt-") && none(["audio", "realtime", "tts", "transcribe", "image", "search", "embedding", "instruct"])
        case .gemini: modelID.contains("gemini-") && none(["embedding", "image", "tts", "audio", "live"])
        case .openRouter: shortlist.contains { $0.slug == modelID }
        }
    }
}

/// One Keychain item per service, on this device only. Keys never enter preferences, the diary or a backup.
struct AIKeyStore: Sendable {
    enum Failure: Error, Equatable { case invalidKey, unavailable }
    let service: String
    init(service: String = "Mivu.AIKeys") { self.service = service }
    @MainActor static var local: AIKeyStore {
        AIKeyStore(service: DiaryLaunch.testID.map { "Mivu.AIKeysTest." + $0.uuidString } ?? "Mivu.AIKeys")
    }

    private func query(_ key: KeyService) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key.rawValue]
    }

    func load(_ key: KeyService) throws -> String? {
        var request = query(key)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw Failure.unavailable }
        return value
    }

    func save(_ value: String, for key: KeyService) throws {
        guard !value.isEmpty, value.utf8.count <= 512,
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else { throw Failure.invalidKey }
        let data = Data(value.utf8)
        let update = SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw Failure.unavailable }
        var item = query(key)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw Failure.unavailable }
    }

    func remove(_ key: KeyService) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.unavailable }
    }
}
