import Foundation

struct CompanionSelection {
    let catalog: CharacterCatalog
    private let defaults: UserDefaults
    private(set) var selectedCharacterID: String

    var selectedCharacter: CharacterDescriptor {
        catalog.resolve(selectedCharacterID)
    }

    init(catalog: CharacterCatalog, defaults: UserDefaults) {
        self.catalog = catalog
        self.defaults = defaults

        let storedID = defaults.string(forKey: "selectedCharacterID")
        let resolvedID = catalog.resolve(storedID).id
        selectedCharacterID = resolvedID
        if storedID != resolvedID {
            defaults.set(resolvedID, forKey: "selectedCharacterID")
        }
    }

    mutating func select(_ id: String) {
        let resolvedID = catalog.resolve(id).id
        guard resolvedID != selectedCharacterID else { return }

        selectedCharacterID = resolvedID
        defaults.set(resolvedID, forKey: "selectedCharacterID")
    }
}
