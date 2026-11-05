import SwiftUI

/// Mockup 7: the running workout above the tab bar on every tab. Tap returns to it.
/// Left untouched for 12 hours, it asks to finish or discard instead.
struct WorkoutBanner: View {
    let session: WorkoutSession
    let restEndsAt: Date?
    let onOpen: () -> Void
    var onFinish: () -> Void = {}
    var onDiscard: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme

    private var title: String { WorkoutRow.title(session) }

    var body: some View {
        // Once a minute, for the spoken minutes and the 12-hour check; the clock itself is drawn by the system.
        TimelineView(.everyMinute) { context in
            Group {
                if session.isStale(now: context.date) { stale } else { running(at: context.date) }
            }
            .font(.subheadline)
            .foregroundStyle(Color.diaryActionText)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.diaryWorkout)
        }
    }

    private func running(at now: Date) -> some View {
        let minutes = max(Int(now.timeIntervalSince(session.performedAt) / 60), 0)
        let resting = restEndsAt.map { $0 > now } ?? false
        return Button(action: onOpen) {
            HStack(spacing: 10) {
                // The dot keeps the light green of the mockup on either purple.
                Circle().fill(Color.diarySuccess.fixed(for: colorScheme == .dark ? .light : .dark)).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).fontWeight(.semibold)
                    if let line = session.nextSetLabel ?? session.exercises.last?.name {
                        Text(line).font(.caption).opacity(0.85)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                if resting { Image(systemName: "timer").font(.footnote.weight(.semibold)) }
                Group {
                    if resting, let restEndsAt { Text(timerInterval: now...restEndsAt, countsDown: true) }
                    else { Text(timerInterval: session.performedAt...Date.distantFuture, countsDown: false) }
                }
                .font(.body.weight(.bold)).monospacedDigit()
                // No digit animation: a clock that animates every second never lets the screen settle.
                .contentTransition(.identity).transaction { $0.animation = nil }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
            }
            .frame(maxHeight: .infinity).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) running, \(minutes) \(minutes == 1 ? "minute" : "minutes")")
        .accessibilityHint("Opens workout.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("workoutBanner")
    }

    private var stale: some View {
        HStack(spacing: 8) {
            Text("Finish \(title)?").fontWeight(.semibold).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Button("Discard", action: onDiscard).frame(minWidth: 44, minHeight: 44)
            Button("Finish", action: onFinish).fontWeight(.semibold).frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}
