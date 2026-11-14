import Foundation
import Testing
@testable import Mivu

@Suite struct KeyServiceTests {
    let store = AIKeyStore(service: "Mivu.AIKeysTest." + UUID().uuidString)

    @Test func keysAreStoredPerService() throws {
        try store.save("fixture-claude", for: .claude)
        try store.save("fixture-gemini", for: .gemini)
        #expect(try store.load(.claude) == "fixture-claude")
        #expect(try store.load(.openAI) == nil)
        try store.remove(.claude)
        #expect(try store.load(.claude) == nil)
        #expect(try store.load(.gemini) == "fixture-gemini")
        try store.remove(.gemini)
    }

    @Test(arguments: ["", "has space", "line\nbreak", String(repeating: "k", count: 513)])
    func rejectsUnusableKeys(_ key: String) {
        #expect(throws: AIKeyStore.Failure.invalidKey) { try store.save(key, for: .openAI) }
    }

    @Test func openAIKeySharesTheExistingOpenAIConsent() {
        #expect(KeyService.openAI.consentKey == "openAISharingConsent")
        #expect(Set(KeyService.allCases.map(\.consentKey)).count == 4)
    }

    @Test func pickerHidesModelsThatCannotChat() {
        #expect(KeyService.claude.lists("claude-haiku-5-5"))
        #expect(!KeyService.openAI.lists("text-embedding-3-small"))
        #expect(!KeyService.gemini.lists("models/gemini-embedding-2"))
        #expect(KeyService.allCases.allSatisfy { $0.lists($0.defaultModel) })
    }
}
