import SwiftUI

/// iPhone Duo layout rules: the inner display is regular/regular in every pose, so
/// "sideways" comes from the window shape. Upright stays the normal phone layout.
enum DuoLayout {
    static let readableWidth: CGFloat = 700

    static func isWide(size: CGSize, horizontal: UserInterfaceSizeClass?, typeSize: DynamicTypeSize) -> Bool {
        horizontal == .regular && size.width > size.height && !typeSize.isAccessibilitySize
    }
}

extension EnvironmentValues {
    @Entry var isWideLayout = false
    @Entry var isHalfFolded = false
    /// The window's real width class, kept before the root forces compact while upright.
    @Entry var windowSizeClass: UserInterfaceSizeClass? = nil
}

/// Measures the window and publishes the Duo layout. While not wide it forces the compact
/// width class, so the upright inner display renders exactly like a normal iPhone.
struct DuoLayoutRoot<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var size = CGSize.zero
    private let forcedWide = DiaryLaunch.isUITest && ProcessInfo.processInfo.arguments.contains("--wide-layout-ui-test")

    var body: some View {
        let wide = forcedWide || DuoLayout.isWide(size: size, horizontal: sizeClass, typeSize: typeSize)
        content
            .environment(\.horizontalSizeClass, wide ? .regular : .compact)
            .environment(\.isWideLayout, wide)
            .environment(\.windowSizeClass, sizeClass)
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
    }
}

private struct DuoReadableWidth: ViewModifier {
    @Environment(\.isWideLayout) private var isWide
    @Environment(\.windowSizeClass) private var windowSizeClass
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: windowSizeClass == .regular && !isWide ? DuoLayout.readableWidth : .infinity)
            .frame(maxWidth: .infinity)
            .background(Color.diaryCanvas)
    }
}

extension View {
    /// Caps upright inner-display content at a readable width; a no-op everywhere else.
    func duoReadableWidth() -> some View { modifier(DuoReadableWidth()) }
}
