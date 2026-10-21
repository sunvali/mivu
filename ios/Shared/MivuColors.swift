import SwiftUI

// Shared with the widget extension so both draw with the same palette.
extension Color {
    private static func adaptive(_ light: UInt32, _ dark: UInt32, highContrastLight: UInt32? = nil, highContrastDark: UInt32? = nil) -> Color {
        Color(uiColor: UIColor { traits in
            let highContrast = traits.accessibilityContrast == .high
            let value = traits.userInterfaceStyle == .dark
                ? (highContrast ? highContrastDark ?? dark : dark)
                : (highContrast ? highContrastLight ?? light : light)
            return UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static let diaryCanvas = adaptive(0xF5F8F8, 0x111516)
    static let diarySurface = adaptive(0xFFFFFF, 0x1D2324)
    static let diaryText = adaptive(0x142023, 0xF4F7F6)
    static let diarySecondary = adaptive(0x53646B, 0xB7C4C8, highContrastLight: 0x34474D, highContrastDark: 0xD5E0E3)
    static let diaryAccent = adaptive(0x006D75, 0x63D5CD, highContrastLight: 0x00545C, highContrastDark: 0x9CEDE6)
    static let diaryActionText = adaptive(0xFFFFFF, 0x092126)
    static let diaryProtein = adaptive(0x195DC2, 0x91BCFF, highContrastLight: 0x124994, highContrastDark: 0xBAD5FF)
    static let diaryCarbs = adaptive(0x925000, 0xF4BC62, highContrastLight: 0x713D00, highContrastDark: 0xFFDBA0)
    static let diaryFat = adaptive(0x7740AD, 0xCCA5F8, highContrastLight: 0x5E2E8E, highContrastDark: 0xE2CAFF)
    static let diarySuccess = adaptive(0x237448, 0x80D5A4, highContrastLight: 0x175A34, highContrastDark: 0xB0EBC6)
    static let diaryWarning = diaryCarbs
    static let diaryError = adaptive(0xB33143, 0xFF9BA6, highContrastLight: 0x8C2030, highContrastDark: 0xFFC2C9)
    static let diaryMessage = adaptive(0x007987, 0x006778)
    static let diarySummarySurface = adaptive(0xEAF5F3, 0x142D2D)
    static let diaryChartSurface = adaptive(0xEDF3FC, 0x19283A)
    static let diaryEnergy = diaryAccent
    static let diaryWeight = diaryProtein
    static let diaryWorkout = diaryFat
    static let diaryLeaf = diaryAccent
    static let diaryRule = adaptive(0xD5DFE1, 0x374346, highContrastLight: 0x9BAEB2, highContrastDark: 0x68777B)
}
