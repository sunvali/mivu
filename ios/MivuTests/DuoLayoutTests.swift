import SwiftUI
import Testing
@testable import Mivu

struct DuoLayoutTests {
    @Test func uprightInnerDisplayIsNotWide() {
        #expect(!DuoLayout.isWide(size: CGSize(width: 669, height: 951), horizontal: .regular, typeSize: .large))
    }

    @Test func sidewaysInnerDisplayIsWide() {
        #expect(DuoLayout.isWide(size: CGSize(width: 951, height: 669), horizontal: .regular, typeSize: .large))
    }

    @Test func compactWidthIsNeverWide() {
        #expect(!DuoLayout.isWide(size: CGSize(width: 951, height: 669), horizontal: .compact, typeSize: .large))
    }

    @Test func accessibilitySizesStaySingleColumn() {
        #expect(!DuoLayout.isWide(size: CGSize(width: 951, height: 669), horizontal: .regular, typeSize: .accessibility3))
    }

    @Test func outerDisplayIsNotWide() {
        #expect(!DuoLayout.isWide(size: CGSize(width: 466, height: 678), horizontal: .compact, typeSize: .large))
    }
}
