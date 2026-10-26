import Foundation
import Testing
import UIKit
@testable import Mivu

@Suite @MainActor struct DiaryCompanionMomentTests {
    private func fixture() async throws -> (URL, DiaryStore, DiaryProfile, DiaryViewModel) {
        let path = URL.temporaryDirectory.appending(path: "CompanionMoment-" + UUID().uuidString)
        let store = DiaryStore(directory: path)
        let profile = adultProfile(name: "Synthetic owner", timeZoneID: "UTC")
        _ = try await store.createProfile(profile)
        _ = try await store.startDay()
        let model = DiaryViewModel(store: store); await model.load(createDefaultProfile: false)
        return (path, store, profile, model)
    }

    private func meal(_ text: String) -> MealDraft { var draft = MealDraft(); draft.text = text; return draft }

    @Test func firstMealOfDayFiresOncePerLocalDay() async throws {
        let (path, store, profile, model) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let first = meal("Synthetic breakfast")
        #expect(await model.capture(first, dayID: try #require(model.activeDay).id))
        let event = try #require(model.companionHabitEvent)
        #expect(event.kind == .firstMealToday && event.profileID == profile.id && event.operationID == first.submissionID)

        #expect(await model.capture(meal("Synthetic lunch"), dayID: try #require(model.activeDay).id))
        #expect(model.companionHabitEvent == event)
        #expect(await model.capture(first, dayID: try #require(model.activeDay).id))
        #expect(model.companionHabitEvent == event)

        #expect(await model.change { _ = try await store.startDay(at: Date().addingTimeInterval(86_400), expectedProfileID: profile.id) })
        let next = meal("Synthetic next-day breakfast")
        #expect(await model.capture(next, dayID: try #require(model.activeDay).id))
        let again = try #require(model.companionHabitEvent)
        #expect(again.kind == .firstMealToday && again.operationID == next.submissionID)
    }

    @Test func firstMealIsDecidedFromTheStateTheWriteProduced() async throws {
        let (path, store, profile, model) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        // A day the view model has not seen yet: the decision cannot rely on anything read before the save.
        let newDay = try await store.startDay(at: Date().addingTimeInterval(86_400), expectedProfileID: profile.id)
        let draft = meal("Synthetic breakfast on a fresh day")
        #expect(await model.capture(draft, dayID: newDay.id))
        let event = try #require(model.companionHabitEvent)
        #expect(event.kind == .firstMealToday && event.operationID == draft.submissionID)
        #expect(await model.capture(meal("Synthetic second meal"), dayID: newDay.id))
        #expect(model.companionHabitEvent == event, "the second meal of the day is not a first")
    }

    @Test func photoAddedEmitsOncePerAttachment() async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let coach = CoachViewModel(diary: f.diary, connection: ChatGPTConnection())
        coach.enterBackground()
        let bytes = try Task10JPEG.tagged()
        #expect(coach.companionPhotoEvent == nil)
        _ = try await coach.attachmentDraft.importSelections([.init { bytes }])
        let event = try #require(coach.companionPhotoEvent)
        #expect(event.kind == .photoAdded && event.operationID == coach.attachmentDraft.submissionID
            && event.profileID == f.diary.selection?.identity.profileID)
        _ = try await coach.attachmentDraft.importSelections([.init { bytes }])
        #expect(coach.companionPhotoEvent == event)
    }

    @Test func lastActiveRoundTripsPerProfile() throws {
        let defaults = try #require(UserDefaults(suiteName: "CompanionLastActive-" + UUID().uuidString))
        let store = CompanionLastActive(defaults: defaults)
        let a = UUID(), b = UUID(), when = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(store.date(for: a) == nil)
        store.record(when, for: a)
        #expect(store.date(for: a) == when)
        #expect(store.date(for: b) == nil)
        store.forget(a)
        #expect(store.date(for: a) == nil)
    }

    @Test func storedLastActiveFromAnEarlierDayYieldsWelcomeBack() throws {
        let defaults = try #require(UserDefaults(suiteName: "CompanionWelcome-" + UUID().uuidString))
        let store = CompanionLastActive(defaults: defaults)
        let profile = UUID(), other = UUID(), now = Date()
        store.record(now.addingTimeInterval(-3 * 86_400), for: profile)
        func greeting(for id: UUID) -> CompanionPose {
            let presentation = CompanionPresentation()
            store.attach(presentation, profileID: id, existingEvents: [], existingSubmissions: [], now: now)
            return presentation.resolve(context: CompanionContext(surface: .today, isTyping: false, isProcessing: false,
                needsRecovery: false, playback: .animated), now: now).pose
        }
        #expect(greeting(for: profile) == .welcomeBack)
        #expect(greeting(for: other) == .greeting)
    }

    @Test func typingPastSixtyCharactersAddsNoFurtherSignal() {
        #expect(CompanionContext.draftSignal(59) != CompanionContext.draftSignal(60))
        #expect(CompanionContext.draftSignal(60) == CompanionContext.draftSignal(61))
        #expect(CompanionContext.draftSignal(61) == CompanionContext.draftSignal(600))
        #expect(CompanionContext.draftSignal(-3) == 0)
    }

    @Test func caretSignalFollowsTheLastWrappedLine() {
        let font = UIFont.systemFont(ofSize: 17)
        #expect(CompanionContext.caretSignal("", width: 200, font: font) == 0)
        let short = CompanionContext.caretSignal("Eggs", width: 200, font: font)
        let longer = CompanionContext.caretSignal("Eggs and toast", width: 200, font: font)
        #expect(short > 0 && longer > short)
        // Once the draft wraps, the caret starts the next line near the field's leading edge again.
        #expect(CompanionContext.caretSignal("Eggs and toast with butter and jam on the side, tea", width: 200, font: font) < longer)
    }
}
