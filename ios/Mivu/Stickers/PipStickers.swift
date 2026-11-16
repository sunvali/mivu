import UIKit

struct PipStickerItem: Identifiable {
    let id: String
    let accessibilityText: String
    let animated: Bool

    var shareURL: URL? { Bundle.main.url(forResource: id, withExtension: animated ? "gif" : "png") }
}

enum PipStickers {
    static let all: [PipStickerItem] = [
        ("hi", "Pip waving hello", true), ("thanks", "Pip saying thank you", false),
        ("love-it", "Pip hugging a fluffy tail, with hearts", false), ("lol", "Pip laughing", false),
        ("ok", "Pip winking with a paw raised", false), ("oops", "Pip blushing, oops", false),
        ("good-night", "Pip curled up asleep", true), ("yum", "Pip enjoying a salad bowl", false),
        ("hungry", "Pip holding an empty bowl", false), ("hydrate", "Pip sipping water", false),
        ("snack", "Pip holding up an apple", false), ("you-got-it", "Pip cheering and hopping", true),
    ].map { PipStickerItem(id: $0.0, accessibilityText: $0.1, animated: $0.2) }

    // https://github.com/WhatsApp/stickers/blob/main/iOS/WAStickersThirdParty/Interoperability.swift
    static let pasteboardType = "net.whatsapp.third-party.sticker-pack"
    private static let whatsAppURL = URL(string: "whatsapp://stickerPack")!

    static func whatsAppPayload(animated: Bool, bundle: Bundle = .main) throws -> Data {
        func file(_ name: String, _ ext: String) throws -> Data {
            guard let url = bundle.url(forResource: name, withExtension: ext) else { throw CocoaError(.fileNoSuchFile) }
            return try Data(contentsOf: url)
        }
        let manifest = try JSONSerialization.jsonObject(
            with: file(animated ? "pip-animated" : "pip-still", "json")) as? [String: Any]
        guard var pack = (manifest?["sticker_packs"] as? [[String: Any]])?.first else { throw CocoaError(.fileReadCorruptFile) }
        let listed = pack["stickers"] as? [[String: Any]] ?? []
        pack["tray_image"] = try file("tray", "png").base64EncodedString()
        pack["stickers"] = try listed.map { entry in
            let id = ((entry["image_file"] as? String) ?? "").replacingOccurrences(of: ".webp", with: "")
            return [
                "image_data": try file(id, "webp").base64EncodedString(),
                "emojis": entry["emojis"] ?? [],
                "accessibility_text": all.first { $0.id == id }?.accessibilityText ?? "",
            ]
        }
        pack["publisher_website"] = "https://mivuapp.com"
        pack["privacy_policy_website"] = "https://mivuapp.com/privacy"
        for key in ["tray_image_file", "image_data_version", "publisher_email", "license_agreement_website"] {
            pack[key] = nil
        }
        return try JSONSerialization.data(withJSONObject: pack)
    }

    static func pasteboardOptions(now: Date) -> [UIPasteboard.OptionsKey: Any] {
        [.localOnly: true, .expirationDate: now + 60]
    }

    @MainActor static func sendToWhatsApp(animated: Bool) throws -> Bool {
        guard UIApplication.shared.canOpenURL(whatsAppURL) else { return false }
        let data = try whatsAppPayload(animated: animated)
        UIPasteboard.general.setItems([[pasteboardType: data]], options: pasteboardOptions(now: .now))
        UIApplication.shared.open(whatsAppURL)
        return true
    }
}
