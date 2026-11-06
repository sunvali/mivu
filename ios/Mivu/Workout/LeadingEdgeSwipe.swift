import SwiftUI

/// The system's screen-edge pan from the left, as Back uses, so it never competes with scrolling or row swipes.
struct LeadingEdgeSwipe: UIGestureRecognizerRepresentable {
    let action: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UIScreenEdgePanGestureRecognizer {
        let recognizer = UIScreenEdgePanGestureRecognizer()
        recognizer.edges = .left
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIScreenEdgePanGestureRecognizer, context: Context) {
        guard recognizer.state == .ended, recognizer.translation(in: recognizer.view).x > 60 else { return }
        action()
    }
}
