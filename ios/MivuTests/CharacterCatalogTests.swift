import Testing
@testable import Mivu

@Suite struct CharacterCatalogTests {
    @Test func productionCatalogContainsOnlyPip() {
        let catalog = CharacterCatalog.bundled

        #expect(catalog.characters.map(\.id) == ["pip"])
        #expect(Set(catalog.characters.map(\.id)).count == catalog.characters.count)
        #expect(catalog.characters.allSatisfy { $0.schemaVersion == 2 })
        #expect(catalog.resolve("pip").displayName == "Pip")
        #expect(catalog.resolve("pip").animationResourcePath == "Characters/pip/pip-rig.json")
        #expect(catalog.resolve(nil).id == "pip")
        #expect(catalog.resolve("removed-character").id == "pip")
        #expect(catalog.resolve("pip").fallbackAssetPrefix == "Pip")
        #expect(catalog.resolve("pip").previewAssetName == "PipPreview")
        #expect(!catalog.showsChooser)
    }

    @Test func oneEntryHidesChooserTwoEntriesShowIt() {
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

        #expect(!CharacterCatalog.bundled.showsChooser)
        #expect(catalog.showsChooser)
        #expect(catalog.resolve("test-companion") == second)
    }
}
