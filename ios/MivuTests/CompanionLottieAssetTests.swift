import CryptoKit
import Foundation
import Testing
@testable import Mivu

@MainActor struct CompanionLottieAssetTests {
    @Test func bundledPipPreservesApprovedArtworkAndNamedSegments() throws {
        let url = try #require(Bundle.main.url(forResource: "pip", withExtension: "json", subdirectory: "Characters/pip"))
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let metadata = try #require(json["meta"] as? [String: Any])
        let expected = "5bef0e0459bf52c26fde44170c4b9419d0d4e4154779f51b0d01fdd1fd9166e1"
        #expect(metadata["sourceSHA256"] as? String == expected)
        let art = try #require(Bundle.main.url(forResource: "pip-artwork", withExtension: "png", subdirectory: "Characters/pip"))
        let digest = SHA256.hash(data: try Data(contentsOf: art)).map { String(format: "%02x", $0) }.joined()
        #expect(digest == expected, "The animation must use the unchanged approved illustration")
        let markers = try #require(json["markers"] as? [[String: Any]])
        let names = Set(markers.compactMap { $0["cm"] as? String })
        let base = ["resting", "blink", "attentive", "thinking", "saved", "reviewed", "recovery", "greeting"]
        #expect(names == Set(base.flatMap { [$0, "coach-" + $0] }))
        let durations = ["resting": MivuMotion.resting, "blink": MivuMotion.blink, "attentive": MivuMotion.attentive, "thinking": MivuMotion.thinking, "saved": MivuMotion.saved, "reviewed": MivuMotion.reviewed, "recovery": MivuMotion.recovery, "greeting": MivuMotion.greeting]
        for marker in markers {
            let name = try #require(marker["cm"] as? String)
            let seconds = try #require(marker["dr"] as? Double) / 60
            #expect(seconds == durations[name.replacingOccurrences(of: "coach-", with: "")], "Presenter and authored playback must share the same duration")
        }
        #expect((json["fr"] as? Double) == 60)
        let layers = try #require(json["layers"] as? [[String: Any]])
        let layerNames = Set(layers.compactMap { $0["nm"] as? String })
        for part in ["head", "left-ear", "right-ear", "torso", "left-paw", "right-paw", "tail", "scarf"] {
            #expect(layerNames.contains(part), "Independent body part missing: \(part)")
        }
    }
}
