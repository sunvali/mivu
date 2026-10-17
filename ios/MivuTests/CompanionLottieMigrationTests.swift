import Foundation
import Testing
@testable import Mivu

@MainActor struct CompanionLottieMigrationTests {
    @Test func shippingCharacterUsesTheApprovedLottieTimeline() throws {
        let path = CharacterCatalog.bundled.resolve("pip").animationResourcePath
        let url = try #require(Bundle.main.url(forResource: path, withExtension: nil))
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        #expect(object?["nm"] as? String == "Pip approved illustration")
    }
}
