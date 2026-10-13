import Foundation
import Testing
@testable import Mivu

@Suite struct DiaryPreferencesDraftTests {
    @Test func sameProfileRefreshMergesUntouchedFieldWithoutDiscardingUnsavedEdit() {
        var profile = DiaryProfile(name: "Synthetic profile")
        var draft = DiaryPreferencesDraft()
        draft.synchronize(profile, restoreGeneration: 0)
        draft.preferences = "Unsaved synthetic restriction"

        profile.timeZoneID = "Europe/London"
        draft.synchronize(profile, restoreGeneration: 0)

        #expect(draft.timezone == "Europe/London")
        #expect(draft.preferences == "Unsaved synthetic restriction")
        let merged = draft.applying(to: profile)
        #expect(merged.timeZoneID == "Europe/London")
        #expect(merged.preferences == "Unsaved synthetic restriction")
    }

    @Test func overlappingExternalEditKeepsDraftVisibleWithoutOverwritingSavedValue() {
        var profile = DiaryProfile(name: "Synthetic profile")
        var draft = DiaryPreferencesDraft()
        draft.synchronize(profile, restoreGeneration: 0)
        draft.preferences = "Unsaved synthetic restriction"

        profile.preferences = "New saved synthetic restriction"
        draft.synchronize(profile, restoreGeneration: 0)

        #expect(draft.preferences == "Unsaved synthetic restriction")
        #expect(draft.hasConflict)
        #expect(draft.applying(to: profile).preferences == "New saved synthetic restriction")
        draft.useSaved(profile)
        #expect(!draft.hasConflict)
        #expect(draft.preferences == "New saved synthetic restriction")
    }
}
