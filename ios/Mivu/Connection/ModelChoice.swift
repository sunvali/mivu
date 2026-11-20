import Foundation

/// The model someone picked. A family follows that family's newer versions; nil pins this exact model.
struct ModelChoice: Codable, Equatable, Sendable {
    var slug: String
    var family: String?
    /// The upgrade they undid: they stay put until a version newer than it appears.
    var declinedSlug: String?
}

enum ModelFamily {
    /// "GPT‑6.2 Sol" → ("sol", [6, 2]). A name in another shape returns nil and is never upgraded.
    static func parse(_ displayName: String) -> (family: String, version: [Int])? {
        let name = displayName.replacingOccurrences(of: "\u{2011}", with: "-").trimmingCharacters(in: .whitespaces)
        guard let match = name.wholeMatch(of: /(?i)gpt-?(\d+(?:\.\d+)*)(?:\s+(.+))?/) else { return nil }
        let version = match.1.split(separator: ".").compactMap { Int($0) }
        return ((match.2.map(String.init) ?? "").lowercased(), version)
    }

    struct Resolution: Equatable { let slug: String; let choice: ModelChoice?; let upgradedFrom: String? }

    /// Which listed model to use. Only listed models are ever returned, so every plan keeps working.
    static func resolve(_ catalog: [AvailableModel], remembered: ModelChoice?, defaultFamily: String?) -> Resolution {
        guard let first = catalog.first else { return Resolution(slug: "", choice: remembered, upgradedFrom: nil) }
        let fallback = Resolution(slug: first.slug, choice: nil, upgradedFrom: nil)
        guard let remembered else {
            return newest(in: defaultFamily?.lowercased(), of: catalog).map { Resolution(slug: $0.slug, choice: nil, upgradedFrom: nil) } ?? fallback
        }
        let listed = catalog.contains { $0.slug == remembered.slug }
        guard let family = remembered.family else { return listed ? Resolution(slug: remembered.slug, choice: remembered, upgradedFrom: nil) : fallback }
        guard let latest = newest(in: family, of: catalog) else { return fallback }
        if latest.slug == remembered.slug || (latest.slug == remembered.declinedSlug && listed) {
            return Resolution(slug: remembered.slug, choice: remembered, upgradedFrom: nil)
        }
        // A retired version moves within its family without a note; there is nothing to undo to.
        return Resolution(slug: latest.slug, choice: ModelChoice(slug: latest.slug, family: family), upgradedFrom: listed ? remembered.slug : nil)
    }

    /// The listed model someone named in chat: a slug, a full name, or a family word for its newest version.
    static func match(_ asked: String, in catalog: [AvailableModel]) -> AvailableModel? {
        let key = asked.replacingOccurrences(of: "\u{2011}", with: "-").trimmingCharacters(in: .whitespaces).lowercased()
        if let exact = catalog.first(where: { $0.slug.lowercased() == key || $0.displayName.replacingOccurrences(of: "\u{2011}", with: "-").lowercased() == key }) { return exact }
        if let wanted = parse(key) {
            return catalog.first { parse($0.displayName).map { $0.family == wanted.family && $0.version == wanted.version } ?? false }
        }
        return newest(in: key, of: catalog)
    }

    /// The highest version listed in a family.
    static func newest(in family: String?, of catalog: [AvailableModel]) -> AvailableModel? {
        guard let family else { return nil }
        return catalog.compactMap { model in parse(model.displayName).flatMap { $0.family == family ? (model, $0.version) : nil } }
            .max { $0.1.lexicographicallyPrecedes($1.1) }?.0
    }
}
