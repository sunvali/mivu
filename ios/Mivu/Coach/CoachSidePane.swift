import SwiftUI

/// The pane beside the Coach chat on a sideways iPhone Duo. Today is its root and whatever the
/// conversation is about is pushed on top, so the system back button returns to Today and a
/// record that closes itself (a deleted meal) lands there too.
struct CoachSidePane: View {
    let coach: CoachViewModel
    let companionRuntime: CompanionRuntime
    @Binding var pane: CoachPane?
    let openDiary: () -> Void
    /// Receipts already shown. Nil until the first look, so opening the app or turning the phone never moves the pane.
    @State private var seen: Set<String>?

    /// The newest exchange's receipts, only while the chat is at its latest page; paging back is not a change.
    private var latestTurn: CoachExchangeSummary? {
        guard let timeline = coach.timeline, let turn = timeline.exchanges.last, timeline.window.isLatest(turn.id) else { return nil }
        return turn
    }

    var body: some View {
        NavigationStack {
            // Pip stays a still image here and Progress shows none, so the rig mounts once.
            TodayView(model: coach.diary, companionOutput: CompanionOutput(pose: .resting, playback: .hidden, reactionID: nil, nextDeadline: nil),
                      companionRuntime: companionRuntime, onCompanionContextChanged: { _ in }, isLiveDay: true)
                .navigationDestination(item: $pane) { pane in
                    switch pane {
                    case .meal(let id): MealDetailView(model: coach.diary, mealID: id)
                    case .workout(let id): WorkoutDetailView(model: coach.diary, sessionID: id)
                    case .day(let date): HistoryView(model: coach.diary, startDate: date).id(date)
                    case .progress: DiaryProgressView(model: coach.diary, openDiary: openDiary, showsCompanion: false)
                    }
                }
        }
        // The system's control strip is on the chat's page now, but this stack still inherits its inset.
        .ignoresSafeArea(.container, edges: .trailing)
        .accessibilityIdentifier("coachSidePane")
        .onChange(of: latestTurn?.receipts.map(\.operationKey), initial: true) { _, _ in land() }
    }

    /// Moves the pane to where a change Coach just made landed.
    private func land() {
        guard let turn = latestTurn else { return }
        let receipts = turn.receipts
        // A sheet, alert or camera anywhere in the app: the change is skipped, not queued, so an edit is never replaced.
        let modalOpen = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?
            .rootViewController?.presentedViewController != nil
        let landing = CoachPane.landing(seen: seen, receipts: receipts, activeDayID: coach.diary.activeDay?.id,
                                        today: turn.displayLocalDate, modalOpen: modalOpen, showing: pane)
        seen = (seen ?? []).union(receipts.map(\.operationKey))
        guard landing.jumps, landing.pane != pane else { return }
        pane = landing.pane
        // Focus stays in the chat; VoiceOver only hears where the change went.
        let place = switch landing.pane {
        case .progress: "Progress"
        case .day(let date): CoachReplyLines.shortDate(date)
        default: "Today"
        }
        AccessibilityNotification.Announcement("Showing \(place)").post()
    }
}
