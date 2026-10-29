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

    private let first = UUID(), second = UUID()

    @Test func firstLoadHighlightsNothing() {
        #expect(DuoLayout.changedMeal(previous: nil, current: [first: 1]) == nil)
    }

    @Test func newMealIsTheChange() {
        #expect(DuoLayout.changedMeal(previous: [first: 1], current: [first: 1, second: 1]) == second)
    }

    @Test func correctedMealIsTheChange() {
        #expect(DuoLayout.changedMeal(previous: [first: 1, second: 1], current: [first: 1, second: 2]) == second)
    }

    @Test func unchangedOrDeletedMealsAreNoChange() {
        #expect(DuoLayout.changedMeal(previous: [first: 1, second: 1], current: [first: 1]) == nil)
    }
}
