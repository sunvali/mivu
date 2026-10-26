import SwiftUI
import Testing
import UIKit
@testable import Mivu

@Suite struct MivuColorsTests {
    private func hex(_ color: Color, in style: UIUserInterfaceStyle) -> UInt32 {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return UInt32((red * 255).rounded()) << 16 | UInt32((green * 255).rounded()) << 8 | UInt32((blue * 255).rounded())
    }

    @Test func fixedVariantIgnoresTheTraitsItIsLaterResolvedIn() {
        let light = Color.diarySurface.fixed(for: .light), dark = Color.diarySurface.fixed(for: .dark)
        #expect(hex(light, in: .light) == 0xFFFFFF && hex(light, in: .dark) == 0xFFFFFF)
        #expect(hex(dark, in: .light) == 0x1D2324 && hex(dark, in: .dark) == 0x1D2324)
    }
}
