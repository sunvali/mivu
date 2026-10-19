import Foundation

struct CharacterDescriptor: Identifiable, Equatable {
    let id: String
    let displayName: String
    let schemaVersion: Int
    let animationResourcePath: String
    let fallbackAssetPrefix: String
    let previewAssetName: String
}

struct CharacterCatalog {
    static let bundled = CharacterCatalog(characters: [
        CharacterDescriptor(
            id: "pip",
            displayName: "Pip",
            schemaVersion: 2,
            animationResourcePath: "Characters/pip/pip-rig.json",
            fallbackAssetPrefix: "Pip",
            previewAssetName: "PipPreview"
        )
    ])

    let characters: [CharacterDescriptor]

    init(characters: [CharacterDescriptor]) {
        let ids = characters.map(\.id)
        precondition(ids.allSatisfy { !$0.isEmpty } && Set(ids).count == ids.count, "Character IDs must be unique and nonempty")
        precondition(characters.allSatisfy { $0.schemaVersion == 2 }, "Unsupported character schema")
        precondition(
            characters.contains {
                $0.id == "pip" && $0.displayName == "Pip" && $0.schemaVersion == 2 &&
                    $0.animationResourcePath == "Characters/pip/pip-rig.json" &&
                    $0.fallbackAssetPrefix == "Pip" && $0.previewAssetName == "PipPreview"
            },
            "The catalog must include Pip fallback assets"
        )
        self.characters = characters
    }

    func resolve(_ id: String?) -> CharacterDescriptor {
        characters.first { $0.id == id } ?? characters.first { $0.id == "pip" }!
    }

    var showsChooser: Bool { characters.count > 1 }
}
