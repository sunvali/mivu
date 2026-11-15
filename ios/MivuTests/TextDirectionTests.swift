import SwiftUI
import Testing
@testable import Mivu

struct TextDirectionTests {
    @Test func directions() {
        #expect(TextDirection.of("סלט עוף") == .rightToLeft)
        #expect(TextDirection.of("سلطة") == .rightToLeft)
        #expect(TextDirection.of("Chicken salad") == .leftToRight)
        // The first letter decides, as in Unicode's first-strong rule: digits are skipped, a Latin unit is not.
        #expect(TextDirection.of("200 גרם סלט") == .rightToLeft)
        #expect(TextDirection.of("200 g סלט") == .leftToRight)
        #expect(TextDirection.of("Салат") == .leftToRight)
        #expect(TextDirection.of("740") == nil)
        #expect(TextDirection.of("") == nil)
    }
}
