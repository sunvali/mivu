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

/// Where Today's workout panel is: the finger's travel while it moves, or settled open.
@Observable final class EdgeSlideState {
    var travel: CGFloat = 0
    var open = false
    var width: CGFloat = 400
    /// 0 closed, 1 open.
    var progress: CGFloat { open ? 1 : min(travel / width, 1) }
    var offset: CGFloat { -width * (1 - progress) }
}

/// Moves the panel. As a modifier its content is not redrawn when only the position changes.
struct EdgeSlideEffect: ViewModifier {
    let slide: EdgeSlideState
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            // The shadow sits on the plain background, so it never re-renders the screen inside.
            .background(Color.diaryCanvas.shadow(color: .black.opacity(slide.open || slide.progress == 0 ? 0 : 0.18), radius: 16).ignoresSafeArea())
            // Reduce Motion fades it in place instead of sliding.
            .offset(x: reduceMotion ? 0 : slide.offset)
            .opacity(reduceMotion ? slide.progress : 1)
            // Taps and VoiceOver switch only once it settles, never mid-drag.
            .allowsHitTesting(slide.open)
            .accessibilityHidden(!slide.open)
            .accessibilityAddTraits(slide.open ? .isModal : [])
    }
}

/// Today dims as the panel comes in.
struct EdgeDim: View {
    let slide: EdgeSlideState
    var body: some View { Color.black.opacity(0.3 * slide.progress).ignoresSafeArea().allowsHitTesting(false) }
}

/// Today's way into a workout: a slim handle on the left edge. Tap it, or drag it (or the edge) to slide the workout in.
struct WorkoutEdgeTab: View {
    let running: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: running ? "figure.strengthtraining.traditional" : "dumbbell.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.diaryWorkout)
                .frame(width: 16, height: 44)
                .background(Color.diarySurface, in: UnevenRoundedRectangle(bottomTrailingRadius: 8, topTrailingRadius: 8))
                .overlay { UnevenRoundedRectangle(bottomTrailingRadius: 8, topTrailingRadius: 8).strokeBorder(Color.diaryRule, lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.08), radius: 4, x: 1)
                // The touch target reaches past the handle, as Apple's minimum asks.
                .frame(width: 44, height: 64, alignment: .leading).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(running ? "Open workout" : "Start workout")
        .accessibilityHint("Or swipe in from the left edge.")
        .accessibilityIdentifier("startWorkout")
    }
}
