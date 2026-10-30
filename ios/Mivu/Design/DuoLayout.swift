import SwiftUI

/// iPhone Duo layout rules: the inner display is regular/regular in every pose, so
/// "sideways" comes from the window shape. Upright stays the normal phone layout.
enum DuoLayout {
    static let readableWidth: CGFloat = 700

    static func isWide(size: CGSize, horizontal: UserInterfaceSizeClass?, typeSize: DynamicTypeSize) -> Bool {
        horizontal == .regular && size.width > size.height && !typeSize.isAccessibilitySize
    }

    enum Posture { case flat, book, table }

    /// Folded part-way, the crease's direction says how the Duo stands: an upright crease is a book,
    /// a level one is a table with a standing half above a flat half.
    static func posture(fold: CGRect?) -> Posture {
        guard let fold else { return .flat }
        return fold.width > fold.height ? .table : .book
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
    @Entry var duoPosture = DuoLayout.Posture.flat
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
    @State private var fold: CGRect?
    private let forcedWide = DiaryLaunch.isUITest && ProcessInfo.processInfo.arguments.contains("--wide-layout-ui-test")
    private let forcedPosture: DuoLayout.Posture? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard DiaryLaunch.isUITest, let index = arguments.firstIndex(of: "--duo-posture-ui-test"), index + 1 < arguments.count else { return nil }
        return switch arguments[index + 1] { case "table": .table; case "book": .book; default: nil }
    }()

    var body: some View {
        let wide = forcedWide || DuoLayout.isWide(size: size, horizontal: sizeClass, typeSize: typeSize)
        content
            .environment(\.horizontalSizeClass, wide ? .regular : .compact)
            .environment(\.isWideLayout, wide)
            .environment(\.windowSizeClass, sizeClass)
            .environment(\.duoPosture, forcedPosture ?? DuoLayout.posture(fold: fold))
            // The whole window: the keyboard shortens the content, and an upright Duo must not read as sideways.
            .background { Color.clear.onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }.ignoresSafeArea() }
            .modifier(FoldReader { fold = $0 })
    }
}

/// The Duo's crease while it is folded part-way, in this view's coordinates; nil when flat or on other iPhones.
private struct FoldReader: ViewModifier {
    let onChange: (CGRect?) -> Void
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onGeometryChange(for: CGRect?.self) { proxy in
                proxy.reservedRegions(kind: .division).first { $0.isActive }?.frame
            } action: { onChange($0) }
        } else { content }
    }
}

/// Two panes that meet exactly at the crease when the Duo is folded part-way, and split evenly otherwise.
/// Built from stacks rather than `ArrangementView`, so `primary` keeps its identity (and scroll position)
/// while `secondary` comes and goes as the Duo turns or folds.
struct DuoSplit<Primary: View, Secondary: View>: View {
    var axis: Axis = .horizontal
    var showsSecondary = true
    /// False splits evenly even across a crease, for when the keyboard has taken over the flat half.
    var followsCrease = true
    @ViewBuilder let primary: Primary
    @ViewBuilder let secondary: Secondary
    @State private var fold: CGRect?

    var body: some View {
        // Only a crease across this split's axis divides it; book splits side by side, table top and bottom.
        let crease = showsSecondary && followsCrease ? fold.flatMap { (axis == .horizontal) == ($0.height > $0.width) ? $0 : nil } : nil
        let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        layout {
            // The crease size goes outside, so a flexible primary can't grow past the crease.
            primary
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(width: axis == .horizontal ? crease?.minX : nil, height: axis == .vertical ? crease?.minY : nil)
            if showsSecondary {
                if let crease { Color.clear.frame(width: axis == .horizontal ? crease.width : nil, height: axis == .vertical ? crease.height : nil) }
                secondary.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .modifier(FoldReader { fold = $0 })
    }
}

/// Sideways, shows `secondary` beside `primary`, meeting at the crease in book pose; otherwise only `primary`.
/// The secondary column lays out like a phone.
struct DuoBeside<Primary: View, Secondary: View>: View {
    @ViewBuilder let primary: Primary
    @ViewBuilder let secondary: Secondary
    @Environment(\.isWideLayout) private var isWide

    var body: some View {
        DuoSplit(showsSecondary: isWide) { primary } secondary: {
            secondary
                .environment(\.isWideLayout, false)
                .environment(\.horizontalSizeClass, .compact)
        }
        .background(Color.diaryCanvas)
    }
}

private struct DuoReadableWidth: ViewModifier {
    let evenWhenWide: Bool
    @Environment(\.isWideLayout) private var isWide
    @Environment(\.windowSizeClass) private var windowSizeClass
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: windowSizeClass == .regular && (evenWhenWide || !isWide) ? DuoLayout.readableWidth : .infinity)
            .frame(maxWidth: .infinity)
            .background(Color.diaryCanvas)
    }
}

extension View {
    /// Caps upright inner-display content at a readable width; a no-op everywhere else.
    /// `evenWhenWide` also caps it sideways, for single-column screens.
    func duoReadableWidth(evenWhenWide: Bool = false) -> some View { modifier(DuoReadableWidth(evenWhenWide: evenWhenWide)) }
}
