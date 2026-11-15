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
    @State private var seen = CoachPaneMemory()
    private struct OpenMeal: Equatable { let id: UUID; let exists: Bool }
    /// Whether the meal open in the pane still exists. Coach's own removals arrive as receipts; this also catches Undo.
    private var openMeal: OpenMeal? {
        if case .meal(let id) = pane { OpenMeal(id: id, exists: coach.diary.meal(id) != nil) } else { nil }
    }

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
                .ignoresSafeArea(.container, edges: .trailing)
                .navigationDestination(item: $pane) { pane in
                    Group {
                        switch pane {
                        case .meal(let id): MealDetailView(model: coach.diary, mealID: id)
                        case .workout(let id): WorkoutDetailView(model: coach.diary, sessionID: id)
                        case .day(let date): HistoryView(model: coach.diary, startDate: date).id(date)
                        case .progress: DiaryProgressView(model: coach.diary, openDiary: openDiary, showsCompanion: false)
                        }
                    }
                    // The system's control strip is on the chat's page, but this stack still inherits its inset.
                    .ignoresSafeArea(.container, edges: .trailing)
                }
        }
        .accessibilityIdentifier("coachSidePane")
        .onChange(of: latestTurn?.receipts.map(\.operationKey), initial: true) { _, _ in land() }
        // A meal that was there and is gone has nothing to show; one still loading was never there.
        .onChange(of: openMeal) { was, now in if let was, let now, was.id == now.id, was.exists, !now.exists { pane = nil } }
    }

    /// Moves the pane to where a change Coach just made landed.
    private func land() {
        guard let owner = coach.timeline?.window.identity, let turn = latestTurn else { return }
        // A sheet, alert or camera anywhere in the app: the change is skipped, not queued, so an edit is never replaced.
        let modalOpen = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?
            .rootViewController?.presentedViewController != nil
        let landing = seen.observe(owner: owner, receipts: turn.receipts, activeDayID: coach.diary.activeDay?.id,
                                   today: turn.displayLocalDate, modalOpen: modalOpen, showing: pane)
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
