import SwiftUI
import Testing
@testable import Mivu

struct TextDirectionTests {
    @Test func directions() {
        #expect(TextDirection.of("סלט עוף") == .rightToLeft)
        #expect(TextDirection.of("سلطة") == .rightToLeft)
        #expect(TextDirection.of("Chicken salad") == .leftToRight)
        // The script with more letters decides; a tie goes right to left. Digits and emoji don't count.
        #expect(TextDirection.of("200 גרם סלט") == .rightToLeft)
        #expect(TextDirection.of("200 g סלט") == .rightToLeft)
        #expect(TextDirection.of("KitKat שוקולד") == .rightToLeft)
        #expect(TextDirection.of("Pizza with פיצה") == .leftToRight)
        #expect(TextDirection.of("قهوة مع حليب") == .rightToLeft)
        #expect(TextDirection.of("200 🍕") == nil)
        #expect(TextDirection.of("Салат") == .leftToRight)
        #expect(TextDirection.of("740") == nil)
        #expect(TextDirection.of("") == nil)
    }
}
