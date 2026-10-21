import SwiftUI
import Observation

struct CoachNavigationOrigin: Equatable, Sendable {
    let selection: DiarySelectionOwnership
    let epoch: UInt64
}

/// One root queue; a saved origin cannot acquire a later selection's authority.
@MainActor @Observable final class CoachNavigationOwner {
    private(set) var request: CoachNavigationRequest?
    private(set) var selection: DiarySelectionOwnership?
    private(set) var epoch: UInt64 = 0
    private var transitioning = false

    func synchronize(selection: DiarySelectionOwnership?, isChangingProfile: Bool) {
        guard self.selection != selection || transitioning != isChangingProfile else { return }
        self.selection = selection; transitioning = isChangingProfile
        invalidate()
    }

    func invalidate() { epoch &+= 1; request = nil }

    func origin(selection: DiarySelectionOwnership?, isChangingProfile: Bool) -> CoachNavigationOrigin? {
        guard let selection, self.selection == selection, !transitioning, !isChangingProfile else { return nil }
        return CoachNavigationOrigin(selection: selection, epoch: epoch)
    }

    func isCurrent(_ origin: CoachNavigationOrigin, selection: DiarySelectionOwnership?, isChangingProfile: Bool) -> Bool {
        !isChangingProfile && !transitioning && self.selection == selection
            && selection == origin.selection && epoch == origin.epoch
    }

    @discardableResult func queue(_ target: CoachSeekTarget?, draft: String? = nil, from origin: CoachNavigationOrigin,
                                  selection: DiarySelectionOwnership?, isChangingProfile: Bool) -> Bool {
        synchronize(selection: selection, isChangingProfile: isChangingProfile)
        guard isCurrent(origin, selection: selection, isChangingProfile: isChangingProfile) else { return false }
        request = CoachNavigationRequest(identity: origin.selection.identity, target: target, requestID: UUID(), draft: draft)
        return true
    }

    func consume(_ requestID: UUID) {
        if request?.requestID == requestID { request = nil }
    }
}

struct OpenDiaryCoachAction {
    var origin: CoachNavigationOrigin?
    var open: @MainActor (CoachSeekTarget?, String?, CoachNavigationOrigin) -> Bool = { _, _, _ in false }

    @MainActor @discardableResult func callAsFunction(_ target: CoachSeekTarget?, draft: String? = nil, expectedSelection: DiarySelectionOwnership) -> Bool {
        guard let origin, origin.selection == expectedSelection else { return false }
        return open(target, draft, origin)
    }
}

extension EnvironmentValues {
    @Entry var openDiaryCoach = OpenDiaryCoachAction()
}
