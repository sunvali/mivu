import Foundation
import Testing
@testable import Mivu

@Suite struct NutritionAPIKeyTests {
    @Test func missingKeyHasNoAutomaticFallback() throws {
        let store = NutritionAPIKeyStore(service: "Mivu.NutritionLookupTest." + UUID().uuidString)
        #expect(try store.load() == nil)
    }
    @Test func syntheticKeyRoundTripsAndCanBeRemoved() throws {
        let store = NutritionAPIKeyStore(service: "Mivu.NutritionLookupTest." + UUID().uuidString)
        defer { try? store.remove() }
        try store.save("synthetic-test-key")
        #expect(try store.load() == "synthetic-test-key")
        try store.remove()
        #expect(try store.load() == nil)
    }
    @Test func namespacesRemainSeparate() throws {
        let first = NutritionAPIKeyStore(service: "Mivu.NutritionLookupTest." + UUID().uuidString)
        let second = NutritionAPIKeyStore(service: "Mivu.NutritionLookupTest." + UUID().uuidString)
        defer { try? first.remove(); try? second.remove() }
        try first.save("synthetic-first-key")
        #expect(try second.load() == nil)
    }
    @Test func invalidReplacementPreservesStoredKey() throws {
        let store = NutritionAPIKeyStore(service: "Mivu.NutritionLookupTest." + UUID().uuidString)
        defer { try? store.remove() }
        try store.save("synthetic-existing-key")
        #expect(throws: NutritionAPIKeyStore.Failure.invalidKey) { try store.save("invalid key") }
        #expect(try store.load() == "synthetic-existing-key")
    }
    @Test func failedKeySavePreservesSettingsInput() {
        var draft = NutritionKeyDraft(text: "synthetic-key")
        #expect(!draft.save { _ in throw NutritionAPIKeyStore.Failure.unavailable })
        #expect(draft.text == "synthetic-key")
        #expect(draft.message == "Could not save this key securely. Your input is still here.")
    }
}
