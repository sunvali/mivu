import Foundation
import Testing
import UIKit
@testable import Mivu

private actor WorkoutReplies {
    private var replies: [CoachInferenceResult]
    init(_ replies: [CoachInferenceResult]) { self.replies = replies }
    func next() throws -> CoachInferenceResult {
        guard !replies.isEmpty else { throw CoachError.limitExceeded }
        return replies.removeFirst()
    }
}

@Suite @MainActor struct DiaryCompanionMomentTests {
    private func fixture() async throws -> (URL, DiaryStore, DiaryProfile, DiaryViewModel) {
        let path = URL.temporaryDirectory.appending(path: "CompanionMoment-" + UUID().uuidString)
        let store = DiaryStore(directory: path)
        let profile = DiaryProfile(name: "Synthetic owner", timeZoneID: "UTC")
        _ = try await store.createProfile(profile)
        _ = try await store.startDay()
        let model = DiaryViewModel(store: store); await model.load(createDefaultProfile: false)
        return (path, store, profile, model)
    }

    private func meal(_ text: String) -> MealDraft { var draft = MealDraft(); draft.text = text; return draft }

    /// What Today's Pip plays for a signal: through the presenter and the runtime's moment, to the gesture's name.
    private func played(_ event: CompanionEvent?) throws -> String {
        let event = try #require(event)
        let presentation = CompanionPresentation()
        presentation.attach(profileID: event.profileID, existingEvents: [], now: event.committedAt)
        presentation.receive(event, now: event.committedAt)
        let output = presentation.resolve(context: CompanionContext(surface: .today, isTyping: false, isProcessing: false,
            needsRecovery: false, playback: .animated), now: event.committedAt)
        let moment = try #require(CompanionRuntime.moment(for: output.pose, tapLevel: output.tapLevel, hour: 9, activity: output.activity))
        let gesture = PipGestureLibrary.gesture(for: moment)
        #expect(output.nextDeadline == event.committedAt.addingTimeInterval(gesture.duration), "the presenter holds the whole move")
        return gesture.name
    }

    private func gym(_ store: DiaryStore, _ profile: DiaryProfile, _ model: DiaryViewModel, mode: LiveWorkoutMode = .live) async throws -> LiveWorkoutModel {
        let bench = WorkoutExercise(name: "Synthetic bench", sets: [WorkoutSet(repetitions: 8, loadKg: 60, done: false)], measure: .weightReps)
        let draft = WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: [bench], activity: "strength")
        let session = mode == .live ? try await store.startWorkout(draft, at: Date(), expectedProfileID: profile.id)
            : WorkoutSession(dayID: UUID(), performedAt: Date().addingTimeInterval(-3_600), timePrecision: .exact, revision: 1, kind: .strength,
                             durationMinutes: 0, exercises: [bench], activity: "strength")
        return LiveWorkoutModel(store: store, profileID: profile.id, session: session, unit: "kg", mode: mode, onSaved: model.noteWorkoutSaved)
    }

    @Test func savedRunPlaysJumpingJack() async throws {
        let (path, store, profile, model) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let date = try #require(model.activeDay).localDate
        var run: WorkoutSession?
        #expect(await model.change {
            run = try await store.createWorkout(localDate: date, draft: WorkoutDraft(kind: .cardio, durationMinutes: 30, exercises: [], activity: "run", state: .finished),
                                                performedAt: nil, expectedProfileID: profile.id)
        })
        #expect(model.companionWorkoutEvent == nil, "only a reported save signals")
        model.noteWorkoutSaved(try #require(run))
        let event = try #require(model.companionWorkoutEvent)
        #expect(event.profileID == profile.id && event.operationID == run?.id)
        #expect(try played(event) == "workout-jumping-jack")
    }

    @Test func savedGymPlaysSquat() async throws {
        let (path, store, profile, model) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        for mode in [LiveWorkoutMode.live, .past] {
            let live = try await gym(store, profile, model, mode: mode)
            await live.tick(exercise: 0, set: 0)
            #expect(await live.finish())
            #expect(model.companionWorkoutEvent?.operationID == live.session.id, "\(mode)")
            #expect(try played(model.companionWorkoutEvent) == "workout-squat")
        }
    }

    @Test func activeTickPlaysNothing() async throws {
        let (path, store, profile, model) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let live = try await gym(store, profile, model)
        await live.tick(exercise: 0, set: 0)
        await live.addSet(exercise: 0)
        await live.update(exercise: 0, set: 1, kg: 62.5, reps: 6, seconds: nil)
        #expect(model.companionWorkoutEvent == nil, "an active workout's changes are not a saved workout")
        // Done on an active workout that is not finished yet never signals either.
        model.noteWorkoutSaved(live.session)
        #expect(model.companionWorkoutEvent == nil)
    }

    @Test func doneHardPlaysBreather() throws {
        func gesture(_ effort: Int?) throws -> String {
            let pose = WorkoutDoneView.pipPose(effort: effort)
            return PipGestureLibrary.gesture(for: try #require(CompanionRuntime.moment(for: pose, tapLevel: 0, hour: 9))).name
        }
        #expect(try gesture(7) == "workout-breather" && gesture(9) == "workout-breather")
        #expect(try gesture(5) == "stretch-reach" && gesture(3) == "stretch-reach" && gesture(nil) == "stretch-reach")
    }

    @Test func coachLoggedWorkoutPlaysSquat() async throws {
        let (path, store, profile, model) = try await fixture()
        defer { try? FileManager.default.removeItem(at: path) }
        let date = try #require(model.activeDay).localDate
        let arguments = #"{"local_date":"\#(date)","kind":"strength","duration_minutes":40,"exercises":[],"performed_at":null,"estimated_burn_kcal":null,"burn_source":null}"#
        let replies = WorkoutReplies([
            CoachInferenceResult(model: "fixture", text: "", calls: [CoachToolCall(id: "w", callID: "w", name: "log_workout", namespace: "mivu", arguments: arguments)], outputItems: []),
            CoachInferenceResult(model: "fixture", text: "Logged", calls: [], outputItems: []),
        ])
        let coach = CoachViewModel(diary: model, connection: ChatGPTConnection(), inference: { { _, _ in try await replies.next() } })
        defer { coach.cancel(); model.enterBackground() }
        coach.draft.text = "Synthetic forty minutes of lifting"
        #expect(await coach.send())
        await coach.waitForWorker()
        let workout = try #require(try await store.snapshotForExport().workouts.first)
        #expect(model.companionWorkoutEvent?.operationID == workout.id && model.companionWorkoutEvent?.profileID == profile.id)
        #expect(try played(model.companionWorkoutEvent) == "workout-squat")
    }

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
