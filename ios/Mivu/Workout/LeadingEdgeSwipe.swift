import SwiftUI

/// The system's screen-edge pan from the left, as Back uses, so it never competes with scrolling or row swipes.
/// It reports the finger's travel while it moves, so what it opens can follow the finger.
struct LeadingEdgeSwipe: UIGestureRecognizerRepresentable {
    let onChanged: (CGFloat) -> Void
    /// Travel and horizontal speed when the finger lifts; zero when the system cancels the swipe.
    let onEnded: (_ travel: CGFloat, _ velocity: CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIScreenEdgePanGestureRecognizer {
        let recognizer = UIScreenEdgePanGestureRecognizer()
        recognizer.edges = .left
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIScreenEdgePanGestureRecognizer, context: Context) {
        let view = recognizer.view
        switch recognizer.state {
        case .began, .changed: onChanged(max(recognizer.translation(in: view).x, 0))
        case .ended: onEnded(max(recognizer.translation(in: view).x, 0), recognizer.velocity(in: view).x)
        case .cancelled, .failed: onEnded(0, 0)
        default: break
        }
    }
}

/// Today's way into a workout: a tab on the left edge. Tap it, or drag it (or the edge) to slide the workout in.
struct WorkoutEdgeTab: View {
    let running: Bool
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = 15

    var body: some View {
        Button(action: action) {
            Image(systemName: running ? "figure.strengthtraining.traditional" : "dumbbell.fill")
                .font(.system(size: min(glyph, 22), weight: .semibold))
                .foregroundStyle(Color.diaryActionText)
                .frame(width: 26, height: 64)
                .background(Color.diaryWorkout, in: UnevenRoundedRectangle(bottomTrailingRadius: 13, topTrailingRadius: 13))
                .shadow(color: .black.opacity(0.14), radius: 6, x: 2)
                // The touch target reaches past the tab, as Apple's minimum asks.
                .frame(width: 44, height: 72, alignment: .leading).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(running ? "Open workout" : "Start workout")
        .accessibilityHint("Or swipe in from the left edge.")
        .accessibilityIdentifier("startWorkout")
    }
}
