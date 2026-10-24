import ActivityKit
import SwiftUI
import WidgetKit

private typealias DayState = DayProgressAttributes.ContentState

/// Calories left in the Dynamic Island and on the Lock Screen; every value arrives in the activity's state.
struct DayProgressLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DayProgressAttributes.self) { context in
            LockScreenProgress(state: context.state, isStale: context.isStale)
                .widgetURL(URL(string: "mivu://today"))
        } dynamicIsland: { context in
            let state = context.state, stale = context.isStale
            return DynamicIsland {
                // Pip and the ring are the same size, so the figure sits on the island's centre line.
                DynamicIslandExpandedRegion(.leading) {
                    PipMark(size: 52).frame(maxHeight: .infinity)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CalorieRing(state: state, isStale: stale, size: 52).frame(maxHeight: .infinity)
                }
                DynamicIslandExpandedRegion(.center) {
                    Headline(state: state, isStale: stale, primary: .white, figureFont: .system(.title, design: .rounded, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !stale { MacroRow(state: state).padding(.top, 6).padding(.horizontal, 12).padding(.bottom, 4) }
                }
            } compactLeading: {
                PipMark(size: 24)
            } compactTrailing: {
                CompactFigure(state: state, isStale: stale)
            } minimal: {
                CalorieRing(state: state, isStale: stale, size: 22)
            }
            .widgetURL(URL(string: "mivu://today"))
            .keylineTint(Color.diaryAccent)
        }
    }
}

private struct CompactFigure: View {
    @Environment(\.redactionReasons) private var redaction
    let state: DayState
    let isStale: Bool

    var body: some View {
        Text(isStale ? "–" : state.compact)
            .font(.system(.subheadline, design: .rounded, weight: .semibold)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.6)
            .foregroundStyle(state.isOver ? Color.diarySecondary : Color.diaryAccent)
            .privacySensitive(state.hideWhenLocked)
            .accessibilityLabel(isStale ? "Open Mivu for today" : redaction.contains(.privacy) ? "Mivu day progress" : state.spoken)
    }
}

/// The Lock Screen banner mirrors the expanded island: Pip, figure, ring, then the macros.
private struct LockScreenProgress: View {
    @Environment(\.colorScheme) private var colorScheme
    let state: DayState
    let isStale: Bool

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                PipMark(size: 56)
                Headline(state: state, isStale: isStale, primary: Color.diaryText,
                         figureFont: .system(.largeTitle, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity)
                CalorieRing(state: state, isStale: isStale, size: 56)
            }
            if !isStale { MacroRow(state: state) }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        // ActivityKit resolves the tint outside these traits; a dynamic surface turned white behind dark-scheme text.
        .activityBackgroundTint(Color.diarySurface.fixed(for: colorScheme))
        .activitySystemActionForegroundColor(Color.diaryText.fixed(for: colorScheme))
    }
}

private struct PipMark: View {
    let size: CGFloat

    var body: some View {
        // A small cut of the approved painted Pip; Live Activity images must stay near their display size.
        Image("PipIsland").resizable().scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
    }
}

private struct Headline: View {
    @Environment(\.redactionReasons) private var redaction
    let state: DayState
    let isStale: Bool
    let primary: Color
    let figureFont: Font

    var body: some View {
        VStack(spacing: 0) {
            if isStale {
                Text("Open Mivu for today").font(.headline).foregroundStyle(primary)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            } else {
                Text(state.figure).font(figureFont).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(state.isOver ? Color.diarySecondary : primary)
                    .privacySensitive(state.hideWhenLocked)
                Text("kcal \(state.word)")
                    .font(.footnote.weight(.medium)).foregroundStyle(Color.diarySecondary).lineLimit(1)
                    .privacySensitive(state.hideWhenLocked)
            }
        }
        .accessibilityElement(children: .ignore)
        // Redacted numbers must not come back through VoiceOver on a locked phone.
        .accessibilityLabel(isStale ? "Open Mivu for today"
                            : redaction.contains(.privacy) ? "Mivu day progress"
                            : state.spoken)
    }
}

private struct CalorieRing: View {
    let state: DayState
    let isStale: Bool
    let size: CGFloat

    var body: some View {
        let fraction = isStale ? 0 : DayState.fraction(state.kcalEaten, state.kcalTarget) ?? 0
        let line = max(size / 10, 2.5)
        ZStack {
            Circle().stroke(Color.diaryAccent.opacity(0.22), lineWidth: line)
            Circle().trim(from: 0, to: fraction)
                .stroke(state.isOver ? Color.diarySecondary : Color.diaryAccent, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if size >= 40 {
                Image(systemName: "flame.fill").font(.system(size: size * 0.32)).foregroundStyle(Color.diaryAccent)
            }
        }
        .padding(line / 2)
        .frame(width: size, height: size)
        .privacySensitive(state.hideWhenLocked)
        .accessibilityHidden(true)
    }
}

/// Three equal columns, so protein, carbs and fat line up under the figure.
private struct MacroRow: View {
    let state: DayState

    var body: some View {
        HStack(spacing: 14) {
            column("Protein", state.protein, state.proteinTarget, Color.diaryProtein, partial: state.isPartial("protein"))
            column("Carbs", state.carbs, state.carbsTarget, Color.diaryCarbs, partial: state.isPartial("carbs"))
            column("Fat", state.fat, state.fatTarget, Color.diaryFat, partial: state.isPartial("fat"))
        }
        .privacySensitive(state.hideWhenLocked)
        .accessibilityHidden(true)
    }

    private func column(_ name: String, _ value: Double?, _ target: Double?, _ tint: Color, partial: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(tint.opacity(0.22)).frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(tint).frame(width: proxy.size.width * (DayState.fraction(value, target) ?? 0))
                    }
                }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(name).font(.caption2.weight(.semibold)).foregroundStyle(tint)
                Spacer(minLength: 0)
                Text(DayState.macroAmount(value, target, partial: partial)).font(.caption2.weight(.medium)).monospacedDigit()
                    .foregroundStyle(Color.diarySecondary)
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

private extension DayState {
    static let under = Self(kcalEaten: 1360, kcalTarget: 2000, protein: 80, proteinTarget: 120, carbs: 150, carbsTarget: 200,
                            fat: 40, fatTarget: 60, hideWhenLocked: true)
    static let over = Self(kcalEaten: 2300, kcalTarget: 2000, protein: 130, proteinTarget: 120, carbs: 260, carbsTarget: 200,
                           fat: 70, fatTarget: 60, hideWhenLocked: true)
    static let noTarget = Self(kcalEaten: 1360, kcalTarget: nil, protein: 80, proteinTarget: nil, carbs: 150, carbsTarget: nil,
                               fat: 40, fatTarget: nil, hideWhenLocked: false)
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: DayProgressAttributes()) {
    DayProgressLiveActivity()
} contentStates: { .under; .over; .noTarget }

#Preview("Compact", as: .dynamicIsland(.compact), using: DayProgressAttributes()) {
    DayProgressLiveActivity()
} contentStates: { .under; .over }

#Preview("Lock Screen", as: .content, using: DayProgressAttributes()) {
    DayProgressLiveActivity()
} contentStates: { .under; .over; .noTarget }
