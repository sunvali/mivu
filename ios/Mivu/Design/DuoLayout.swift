import SwiftUI

/// iPhone Duo layout rules: the inner display is regular/regular in every pose, so
/// "sideways" comes from the window shape. Upright stays the normal phone layout.
enum DuoLayout {
    static let readableWidth: CGFloat = 700

    static func isWide(size: CGSize, horizontal: UserInterfaceSizeClass?, typeSize: DynamicTypeSize) -> Bool {
        horizontal == .regular && size.width > size.height && !typeSize.isAccessibilitySize
    }

    /// The meal that just appeared or was revised (meal ID → revision), so the live day beside
    /// Coach can light it up. Nothing on first load.
    static func changedMeal(previous: [UUID: Int]?, current: [UUID: Int]) -> UUID? {
        guard let previous else { return nil }
        return current.first { id, revision in previous[id].map { $0 < revision } ?? true }?.key
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
    @State private var halfFolded = false
    private let forcedWide = DiaryLaunch.isUITest && ProcessInfo.processInfo.arguments.contains("--wide-layout-ui-test")

    var body: some View {
        let wide = forcedWide || DuoLayout.isWide(size: size, horizontal: sizeClass, typeSize: typeSize)
        content
            .environment(\.horizontalSizeClass, wide ? .regular : .compact)
            .environment(\.isWideLayout, wide)
            .environment(\.windowSizeClass, sizeClass)
            .environment(\.isHalfFolded, halfFolded)
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            .background {
                if #available(iOS 27.1, *) { HingeReader { halfFolded = $0 } }
            }
    }
}

/// Reports whether the Duo's hinge is partly open (propped on a table); always false on other iPhones.
@available(iOS 27.1, *)
private struct HingeReader: UIViewRepresentable {
    let onChange: (Bool) -> Void
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.addInteraction(UIHingeInteraction { _, update in onChange(update.hinge?.status == .partiallyOpen) })
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {}
}

/// Sideways, shows `secondary` beside `primary` in an even split; otherwise only `primary`.
/// The secondary column lays out like a phone, and `primary` keeps its identity across the switch.
struct DuoBeside<Primary: View, Secondary: View>: View {
    @ViewBuilder let primary: Primary
    @ViewBuilder let secondary: Secondary
    @Environment(\.isWideLayout) private var isWide

    var body: some View {
        HStack(spacing: 0) {
            primary
            if isWide {
                secondary
                    .environment(\.isWideLayout, false)
                    .environment(\.horizontalSizeClass, .compact)
            }
        }
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
