import Testing
@testable import Mivu

/// Synthetic catalogs only; real names arrive from the person's own account.
struct ModelChoiceTests {
    private func model(_ name: String) -> AvailableModel {
        AvailableModel(slug: name.lowercased().replacingOccurrences(of: " ", with: "-"), displayName: name)
    }
    private var plus: [AvailableModel] { [model("GPT-6.1 Sol"), model("GPT-6.2 Sol"), model("GPT-6.2 Astra")] }
    private var go: [AvailableModel] { [model("GPT-6.2 Go")] }

    @Test func parsesFamilyAndVersion() {
        #expect(ModelFamily.parse("GPT\u{2011}6.2 Sol")! == ("sol", [6, 2]))
        #expect(ModelFamily.parse("GPT-6.2 Sol Mini")! == ("sol mini", [6, 2]))
        #expect(ModelFamily.parse("GPT-6.2")! == ("", [6, 2]))
        #expect(ModelFamily.parse("o4-mini") == nil)
    }

    @Test func newcomerGetsDefaultFamilyNewest() {
        let result = ModelFamily.resolve(plus, remembered: nil, defaultFamily: "Sol")
        #expect(result == .init(slug: "gpt-6.2-sol", choice: nil, upgradedFrom: nil))
    }

    @Test func missingDefaultFamilyUsesFirst() {
        #expect(ModelFamily.resolve(go, remembered: nil, defaultFamily: "Astra").slug == "gpt-6.2-go")
        #expect(ModelFamily.resolve(plus, remembered: nil, defaultFamily: nil).slug == "gpt-6.1-sol")
    }

    @Test func upgradesWithinFamilyOnly() {
        let sol = ModelFamily.resolve(plus, remembered: ModelChoice(slug: "gpt-6.1-sol", family: "sol"), defaultFamily: nil)
        #expect(sol == .init(slug: "gpt-6.2-sol", choice: ModelChoice(slug: "gpt-6.2-sol", family: "sol"), upgradedFrom: "gpt-6.1-sol"))
        let astra = ModelChoice(slug: "gpt-6.2-astra", family: "astra")
        #expect(ModelFamily.resolve(plus, remembered: astra, defaultFamily: "Sol") == .init(slug: "gpt-6.2-astra", choice: astra, upgradedFrom: nil))
    }

    @Test func declinedUpgradeHoldsUntilNewer() {
        let held = ModelChoice(slug: "gpt-6.1-sol", family: "sol", declinedSlug: "gpt-6.2-sol")
        #expect(ModelFamily.resolve(plus, remembered: held, defaultFamily: nil) == .init(slug: "gpt-6.1-sol", choice: held, upgradedFrom: nil))
        let newer = ModelFamily.resolve(plus + [model("GPT-6.3 Sol")], remembered: held, defaultFamily: nil)
        #expect(newer == .init(slug: "gpt-6.3-sol", choice: ModelChoice(slug: "gpt-6.3-sol", family: "sol"), upgradedFrom: "gpt-6.1-sol"))
    }

    @Test func lostFamilyForgets() {
        let result = ModelFamily.resolve(go, remembered: ModelChoice(slug: "gpt-6.2-astra", family: "astra"), defaultFamily: "Sol")
        #expect(result == .init(slug: "gpt-6.2-go", choice: nil, upgradedFrom: nil))
    }

    @Test func retiredVersionMovesWithinFamilyQuietly() {
        let catalog = [model("GPT-6.2 Sol"), model("GPT-6.2 Astra")]
        let result = ModelFamily.resolve(catalog, remembered: ModelChoice(slug: "gpt-6.1-sol", family: "sol"), defaultFamily: nil)
        #expect(result == .init(slug: "gpt-6.2-sol", choice: ModelChoice(slug: "gpt-6.2-sol", family: "sol"), upgradedFrom: nil))
    }

    @Test func unparsedNamePinsExactly() {
        let catalog = [model("o4-mini"), model("GPT-6.2 Sol")]
        let pinned = ModelChoice(slug: "o4-mini", family: nil)
        #expect(ModelFamily.resolve(catalog, remembered: pinned, defaultFamily: "Sol") == .init(slug: "o4-mini", choice: pinned, upgradedFrom: nil))
        #expect(ModelFamily.resolve(go, remembered: pinned, defaultFamily: nil) == .init(slug: "gpt-6.2-go", choice: nil, upgradedFrom: nil))
    }

    @Test func emptyCatalog() {
        let choice = ModelChoice(slug: "gpt-6.2-sol", family: "sol")
        #expect(ModelFamily.resolve([], remembered: choice, defaultFamily: "Sol") == .init(slug: "", choice: choice, upgradedFrom: nil))
    }
}
