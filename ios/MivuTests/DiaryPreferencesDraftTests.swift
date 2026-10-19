import Foundation
import Testing
@testable import Mivu

@Suite struct DiaryPreferencesDraftTests {
    @Test func missingProfileUsesDeviceTimezoneAndSavedProfileKeepsItsZone() {
        var draft = DiaryPreferencesDraft()
        draft.synchronize(nil, restoreGeneration: 0)
        #expect(draft.timezone == TimeZone.current.identifier)
        let profile = DiaryProfile(name: "Synthetic", timeZoneID: "Asia/Jerusalem")
        draft.synchronize(profile, restoreGeneration: 0)
        #expect(draft.timezone == "Asia/Jerusalem")
        draft.useSaved(nil)
        #expect(draft.timezone == TimeZone.current.identifier)
        #expect(!draft.isDirty)
    }

    @Test func isDirtyTracksEditsSaveSynchronizationConflictAndRevert() {
        var profile = DiaryProfile(name: "Synthetic profile")
        var draft = DiaryPreferencesDraft()
        draft.synchronize(profile, restoreGeneration: 0)
        #expect(!draft.isDirty)

        draft.timezone = "Europe/London"
        draft.preferences = "Synthetic preference"
        #expect(draft.isDirty)

        profile = draft.applying(to: profile)
        draft.synchronize(profile, restoreGeneration: 0)
        #expect(!draft.isDirty)

        draft.preferences = "Unsaved synthetic preference"
        profile.preferences = "Concurrent saved preference"
        draft.synchronize(profile, restoreGeneration: 0)
        #expect(draft.preferences == "Unsaved synthetic preference")
        #expect(draft.hasConflict)
        #expect(draft.isDirty)

        draft.useSaved(profile)
        #expect(!draft.isDirty)
    }

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
