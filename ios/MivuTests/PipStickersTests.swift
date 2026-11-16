import Testing
import UIKit
@testable import Mivu

@Suite struct PipStickersTests {
    private static let ids = ["hi", "thanks", "love-it", "lol", "ok", "oops", "good-night",
                              "yum", "hungry", "hydrate", "snack", "you-got-it"]

    @Test func whatsAppPayloadMatchesThePack() throws {
        for (animated, identifier, name, count) in [(false, "mivu-pip-still", "Pip", 9),
                                                    (true, "mivu-pip-animated", "Pip moves", 3)] {
            let json = try #require(JSONSerialization.jsonObject(
                with: PipStickers.whatsAppPayload(animated: animated)) as? [String: Any])
            #expect(json["identifier"] as? String == identifier)
            #expect(json["name"] as? String == name)
            #expect(json["publisher"] as? String == "Mivu")
            #expect(json["publisher_website"] as? String == "https://mivuapp.com")
            #expect(json["privacy_policy_website"] as? String == "https://mivuapp.com/privacy")
            #expect(json["animated_sticker_pack"] as? Bool == animated)
            let trayText = try #require(json["tray_image"] as? String)
            let tray = try #require(Data(base64Encoded: trayText))
            let trayImage = try #require(UIImage(data: tray))
            #expect(trayImage.size == CGSize(width: 96, height: 96) && trayImage.scale == 1)
            let stickers = try #require(json["stickers"] as? [[String: Any]])
            #expect(stickers.count == count)
            let manifestURL = try #require(Bundle.main.url(forResource: animated ? "pip-animated" : "pip-still", withExtension: "json"))
            let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
            let files = try #require((manifest["sticker_packs"] as? [[String: Any]])?.first?["stickers"] as? [[String: Any]])
            #expect(files.count == stickers.count)
            for (sticker, file) in zip(stickers, files) {
                let dataText = try #require(sticker["image_data"] as? String)
                let data = try #require(Data(base64Encoded: dataText))
                let name = try #require(file["image_file"] as? String)
                let bundled = try Data(contentsOf: #require(Bundle.main.url(forResource: name, withExtension: nil)))
                #expect(data == bundled, "\(name)")
                #expect(data.prefix(4) == Data("RIFF".utf8))
                #expect((1...3).contains((sticker["emojis"] as? [String])?.count ?? 0))
                let text = sticker["accessibility_text"] as? String
                #expect(PipStickers.all.contains { $0.accessibilityText == text && $0.animated == animated })
            }
        }
    }

    @Test func stickerListMatchesTheLineup() {
        #expect(PipStickers.all.map(\.id) == Self.ids)
        #expect(PipStickers.all.allSatisfy { $0.shareURL != nil })
    }

    @Test func pasteboardStaysLocalAndExpires() {
        let now = Date(timeIntervalSince1970: 1_000)
        let options = PipStickers.pasteboardOptions(now: now)
        #expect(options[.localOnly] as? Bool == true)
        #expect(options[.expirationDate] as? Date == now + 60)
    }
}
