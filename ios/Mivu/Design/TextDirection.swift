import SwiftUI

/// The direction text carries by itself, so a Hebrew note reads right to left on an English phone and back.
enum TextDirection {
    /// Direction of the script with more letters, so "KitKat שוקולד" reads right to left; a tie goes right to left.
    /// Nil when the text has no letters.
    static func of(_ text: String) -> LayoutDirection? {
        // Hebrew, Arabic, Syriac, Thaana, NKo and their presentation forms.
        let rightToLeft: [ClosedRange<UInt32>] = [0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF]
        let letters = text.unicodeScalars.filter(\.properties.isAlphabetic)
        guard !letters.isEmpty else { return nil }
        let right = letters.count { letter in rightToLeft.contains { $0.contains(letter.value) } }
        return right * 2 >= letters.count ? .rightToLeft : .leftToRight
    }
}

extension View {
    /// Lays this text out by its own content, falling back to the surrounding direction.
    func directionFromContent(_ text: String) -> some View {
        modifier(ContentDirection(direction: TextDirection.of(text)))
    }
}

private struct ContentDirection: ViewModifier {
    let direction: LayoutDirection?
    @Environment(\.layoutDirection) private var surrounding
    func body(content: Content) -> some View {
        content.environment(\.layoutDirection, direction ?? surrounding)
    }
}
