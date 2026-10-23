import Foundation

/// A one-shot reaction's lifetime must cover its gesture (`PipGestureLibrary`); a test holds each to the authored length.
enum MivuMotion {
    static let numeric: TimeInterval = 0.25
    static let coachFollow: TimeInterval = 0.2
    static let status: TimeInterval = 0.18
    static let greeting: TimeInterval = 0.9
    static let submitted: TimeInterval = 0.8
    static let saved: TimeInterval = 0.45
    static let reviewed: TimeInterval = 0.65
    static let firstMealToday: TimeInterval = 1.0
    static let dayComplete: TimeInterval = 1.4
    static let curious: TimeInterval = 1.0
    static let tapped: TimeInterval = 0.8
    static let patted: TimeInterval = 1.3
    static let welcomeBack: TimeInterval = 1.6
    static let progressEntrance: TimeInterval = 1.4
    static let progressRange: TimeInterval = 0.9
    static let progressTap: TimeInterval = 0.8
    static let feedbackLifetime: TimeInterval = 10
}
