import ActivityKit
import SwiftUI
import WidgetKit

private typealias WorkoutState = WorkoutActivityAttributes.ContentState

/// The running workout: rest countdown with the next set, or elapsed time with the current exercise.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenWorkout(title: context.attributes.title, state: shown(context))
                .widgetURL(URL(string: "mivu://today"))
        } dynamicIsland: { context in
            let state = shown(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { WorkoutMark(size: 44).frame(maxHeight: .infinity) }
                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutClock(state: state).font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(.white)
                        .frame(maxWidth: 96, maxHeight: .infinity, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Caption(title: context.attributes.title, state: state, primary: .white).frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(Color.diaryWorkout).accessibilityHidden(true)
            } compactTrailing: {
                // A timer's text takes all the width it is offered; a fixed frame keeps the island small.
                WorkoutClock(state: state).font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.diaryWorkout).frame(width: 48, alignment: .trailing)
            } minimal: {
                Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(Color.diaryWorkout).accessibilityHidden(true)
            }
            .widgetURL(URL(string: "mivu://today"))
            .keylineTint(Color.diaryWorkout)
        }
    }
}

/// The activity goes stale when its rest ends, so the rest is over there even before Mivu wakes to say so.
private func shown(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> WorkoutState {
    var state = context.state
    if context.isStale { state.restEndsAt = nil }
    return state
}

/// Mockup 8: the workout tile, "Rest" with the next set (or the workout and its exercise), and the time.
private struct LockScreenWorkout: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let state: WorkoutState

    var body: some View {
        HStack(spacing: 12) {
            WorkoutMark(size: 44)
            Caption(title: title, state: state, primary: Color.diaryText).frame(maxWidth: .infinity, alignment: .leading)
            WorkoutClock(state: state).font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(Color.diaryText)
                .frame(maxWidth: 110, alignment: .trailing)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .activityBackgroundTint(Color.diarySurface.fixed(for: colorScheme))
        .activitySystemActionForegroundColor(Color.diaryText.fixed(for: colorScheme))
    }
}

private struct Caption: View {
    @Environment(\.redactionReasons) private var redaction
    let title: String
    let state: WorkoutState
    let primary: Color

    var body: some View {
        let resting = state.isResting(at: .now)
        // "Hide when locked" leaves only "Workout" and the time, no names.
        let hidden = state.hideWhenLocked && redaction.contains(.privacy)
        VStack(alignment: .leading, spacing: 2) {
            Text(hidden ? "Workout" : resting ? "Rest" : title).font(.headline).foregroundStyle(primary).lineLimit(1)
            if !hidden, let line = state.line {
                Text(resting ? "Next: \(line)" : line).font(.subheadline).foregroundStyle(Color.diarySecondary).lineLimit(1)
                    .privacySensitive(state.hideWhenLocked)
            }
        }
        .minimumScaleFactor(0.8)
    }
}

/// Counts down a rest, otherwise up from the start; drawn by the system, so it runs while Mivu sleeps.
private struct WorkoutClock: View {
    let state: WorkoutState

    var body: some View {
        Group {
            if let end = state.restEndsAt, end > .now {
                Text(timerInterval: Date.now...end, countsDown: true)
            } else {
                Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
            }
        }
        .monospacedDigit().lineLimit(1).multilineTextAlignment(.trailing)
    }
}

private struct WorkoutMark: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "figure.strengthtraining.traditional").font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size).background(Color.diaryWorkout, in: .rect(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

private extension WorkoutState {
    static let resting = Self(startedAt: .now.addingTimeInterval(-1_450), restEndsAt: .now.addingTimeInterval(72),
                              exercise: "Bench press", nextSet: "set 3", hideWhenLocked: false)
    static let lifting = Self(startedAt: .now.addingTimeInterval(-1_450), exercise: "Bench press", nextSet: "set 2", hideWhenLocked: false)
}

#Preview("Lock Screen", as: .content, using: WorkoutActivityAttributes(title: "Push day")) {
    WorkoutLiveActivity()
} contentStates: { .resting; .lifting }

#Preview("Expanded", as: .dynamicIsland(.expanded), using: WorkoutActivityAttributes(title: "Push day")) {
    WorkoutLiveActivity()
} contentStates: { .resting; .lifting }
