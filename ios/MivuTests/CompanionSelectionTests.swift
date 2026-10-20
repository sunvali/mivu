import Foundation
import Testing
@testable import Mivu

@Suite struct CompanionSelectionTests {
    @Test func selectionPersistsAcrossRecreation() throws {
        let suite = "CompanionSelectionTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let pip = CharacterCatalog.bundled.resolve("pip")
        let second = CharacterDescriptor(
            id: "test-companion",
            displayName: "Test Companion",
            schemaVersion: 2,
            animationResourcePath: pip.animationResourcePath,
            fallbackAssetPrefix: pip.fallbackAssetPrefix,
            previewAssetName: pip.previewAssetName
        )
        let catalog = CharacterCatalog(characters: [pip, second])
        var selection = CompanionSelection(catalog: catalog, defaults: defaults)

        selection.select("test-companion")
        let restored = CompanionSelection(catalog: catalog, defaults: defaults)
        #expect(restored.selectedCharacterID == "test-companion")
        #expect(restored.selectedCharacter == second)
    }

    @Test func invalidStoredIDNormalizesToPip() throws {
        let suite = "CompanionSelectionTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("removed-character", forKey: "selectedCharacterID")

        let selection = CompanionSelection(catalog: .bundled, defaults: defaults)

        #expect(selection.selectedCharacterID == "pip")
        #expect(selection.selectedCharacter.id == "pip")
        #expect(defaults.string(forKey: "selectedCharacterID") == "pip")
        #expect(!selection.catalog.showsChooser)
    }

    @Test func unknownOrMissingIDResolvesToPip() throws {
        let suite = "CompanionSelectionTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let selection = CompanionSelection(catalog: .bundled, defaults: defaults)

        #expect(selection.selectedCharacterID == "pip")
        #expect(defaults.string(forKey: "selectedCharacterID") == "pip")
        #expect(selection.catalog.resolve("removed-character").id == "pip")
    }

    @Test func selectingUnknownIDFallsBackToPip() throws {
        let suite = "CompanionSelectionTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var selection = CompanionSelection(catalog: .bundled, defaults: defaults)

        selection.select("unknown-character")

        #expect(selection.selectedCharacterID == "pip")
        #expect(selection.selectedCharacter.id == "pip")
        #expect(defaults.string(forKey: "selectedCharacterID") == "pip")
    }

    @Test func sameIDSelectionDoesNotChangeIdentity() throws {
        let suite = "CompanionSelectionTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var selection = CompanionSelection(catalog: .bundled, defaults: defaults)

        selection.select("pip")
        let storedID = defaults.string(forKey: "selectedCharacterID")
        selection.select("pip")

        #expect(selection.selectedCharacterID == "pip")
        #expect(selection.selectedCharacter.id == "pip")
        #expect(defaults.string(forKey: "selectedCharacterID") == storedID)
    }
}
