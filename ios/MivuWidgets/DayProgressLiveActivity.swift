import ActivityKit
import SwiftUI
import WidgetKit

/// Calories left in the Dynamic Island and on the Lock Screen; every value arrives in the activity's state.
struct DayProgressLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DayProgressAttributes.self) { context in
            DayProgressSummary(state: context.state, isStale: context.isStale, pipHeight: 56)
                .padding(16)
                .activityBackgroundTint(Color.diarySurface)
                .activitySystemActionForegroundColor(Color.diaryText)
                .widgetURL(URL(string: "mivu://today"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    DayProgressSummary(state: context.state, isStale: context.isStale, pipHeight: 48)
                }
            } compactLeading: {
                pip(height: 22)
            } compactTrailing: {
                figure(context.isStale ? "–" : context.state.compact, state: context.state).font(.subheadline.weight(.semibold))
            } minimal: {
                figure(context.isStale ? "–" : context.state.figure, state: context.state).font(.caption.weight(.semibold))
            }
            .widgetURL(URL(string: "mivu://today"))
            .keylineTint(Color.diaryAccent)
        }
    }

    private func figure(_ text: String, state: DayProgressAttributes.ContentState) -> some View {
        Text(text).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            .foregroundStyle(state.isOver ? Color.diarySecondary : Color.diaryAccent)
            .privacySensitive(state.hideWhenLocked)
            .accessibilityLabel(state.spoken)
    }
}

private func pip(height: CGFloat) -> some View {
    // The approved painted Pip already used by the Home Screen widget; never redacted.
    Image("PipWave").resizable().scaledToFit().frame(height: height).accessibilityHidden(true)
}

/// The expanded island and Lock Screen layout: Pip, the big figure, then protein, carbs and fat.
private struct DayProgressSummary: View {
    let state: DayProgressAttributes.ContentState
    let isStale: Bool
    let pipHeight: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            pip(height: pipHeight)
            if isStale {
                Text("Open Mivu for today").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(state.figure).font(.title.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                            .foregroundStyle(state.isOver ? Color.diarySecondary : .primary)
                        Text(state.word).font(.headline).foregroundStyle(Color.diarySecondary)
                        if state.hasPending {
                            Text("+ pending").font(.caption).foregroundStyle(Color.diarySecondary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(state.spoken + (state.hasPending ? " More meals pending." : ""))
                    HStack(spacing: 10) {
                        macro("P", state.protein, state.proteinTarget, Color.diaryProtein)
                        macro("C", state.carbs, state.carbsTarget, Color.diaryCarbs)
                        macro("F", state.fat, state.fatTarget, Color.diaryFat)
                    }
                    .accessibilityHidden(true)
                }
                .privacySensitive(state.hideWhenLocked)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func macro(_ letter: String, _ value: Double?, _ target: Double?, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(DayProgressAttributes.ContentState.macroLabel(letter, value, target))
                .font(.caption2.weight(.medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(Color.diarySecondary)
            if let fraction = DayProgressAttributes.ContentState.fraction(value, target) {
                Capsule().fill(tint.opacity(0.2)).frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in Capsule().fill(tint).frame(width: proxy.size.width * fraction) }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension DayProgressAttributes.ContentState {
    static let under = Self(kcalEaten: 1360, kcalTarget: 2000, protein: 80, proteinTarget: 120, carbs: 150, carbsTarget: 200,
                            fat: 40, fatTarget: 60, hasPending: false, hideWhenLocked: true)
    static let over = Self(kcalEaten: 2300, kcalTarget: 2000, protein: 130, proteinTarget: 120, carbs: 260, carbsTarget: 200,
                           fat: 70, fatTarget: 60, hasPending: false, hideWhenLocked: true)
    static let pending = Self(kcalEaten: 0, kcalTarget: 2000, protein: nil, proteinTarget: 120, carbs: nil, carbsTarget: 200,
                              fat: nil, fatTarget: 60, hasPending: true, hideWhenLocked: false)
    static let noTarget = Self(kcalEaten: 1360, kcalTarget: nil, protein: 80, proteinTarget: nil, carbs: 150, carbsTarget: nil,
                               fat: 40, fatTarget: nil, hasPending: false, hideWhenLocked: false)
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: DayProgressAttributes()) {
    DayProgressLiveActivity()
} contentStates: { .under; .over; .pending; .noTarget }

#Preview("Compact", as: .dynamicIsland(.compact), using: DayProgressAttributes()) {
    DayProgressLiveActivity()
} contentStates: { .under; .over }

#Preview("Lock Screen", as: .content, using: DayProgressAttributes()) {
    DayProgressLiveActivity()
} contentStates: { .under; .over; .pending; .noTarget }
