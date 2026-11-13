import Foundation
import Testing
@testable import Mivu

@MainActor @Suite struct MachineRecognizerTests {
    private let photo = Data([255, 216, 255, 224] + Array(repeating: 0, count: 16))

    private func recognizer(_ text: String) -> MachineRecognizer {
        MachineRecognizer { _, _ in CoachInferenceResult(model: "synthetic", text: text, calls: [], outputItems: []) }
    }

    @Test func singleMatchAdds() async {
        let guess = await recognizer(#"{"best": "lat-pulldown", "options": ["lat-pulldown"]}"#).recognize(jpeg: photo)
        #expect(guess == MachineGuess(best: "lat-pulldown", options: ["lat-pulldown"]))
    }

    @Test func multiUseReturnsOptions() async {
        let text = "```json\n{\"best\": \"seated-cable-row\", \"options\": [\"face-pull\", \"seated-cable-row\", \"cable-curl\", \"triceps-pushdown\", \"cable-crossover\"]}\n```"
        let guess = await recognizer(text).recognize(jpeg: photo)
        #expect(guess?.best == "seated-cable-row")
        #expect(guess?.options.count == 4)
        #expect(guess?.options.first == "seated-cable-row")
    }

    @Test func unknownIDsDropped() async {
        // A free-weight lift and a made-up ID are not machines in the catalog.
        let guess = await recognizer(#"{"best": "leg-press", "options": ["barbell-bench-press", "rocket-sled", "leg-press", "hack-squat"]}"#).recognize(jpeg: photo)
        #expect(guess == MachineGuess(best: "leg-press", options: ["leg-press", "hack-squat"]))
        #expect(await recognizer(#"{"best": "rocket-sled", "options": ["leg-press"]}"#).recognize(jpeg: photo) == nil)
    }

    @Test func garbageReturnsNil() async {
        #expect(await recognizer("I think it is a rowing machine.").recognize(jpeg: photo) == nil)
        #expect(await recognizer("{\"best\": 3}").recognize(jpeg: photo) == nil)
    }

    @Test func throwingInferenceReturnsNil() async {
        let failing = MachineRecognizer { _, _ in throw ResponsesClient.Failure.invalidInput }
        #expect(await failing.recognize(jpeg: photo) == nil)
    }

    @Test func requestSendsOnlyThePhotoAndMachineNames() async {
        nonisolated(unsafe) var sent: [CoachInferenceInput] = []
        let spy = MachineRecognizer { input, namespace in
            sent = input; #expect(namespace == nil)
            return CoachInferenceResult(model: "synthetic", text: "{}", calls: [], outputItems: [])
        }
        _ = await spy.recognize(jpeg: photo)
        guard case let .message(role, text, images)? = sent.first else { Issue.record("no message"); return }
        #expect(role == .user && images == [photo] && sent.count == 1)
        #expect(text.contains("lat-pulldown") && !text.contains("barbell-bench-press"))
    }

    @Test func appleProviderSkipped() {
        #expect(MachineRecognizer.offered(provider: .chatGPT, connected: true))
        #expect(!MachineRecognizer.offered(provider: .apple, connected: true))
        #expect(!MachineRecognizer.offered(provider: .chatGPT, connected: false))
    }

    @Test func dismissKeepsBestGuess() async throws {
        let root = URL.temporaryDirectory.appending(path: "Machine-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root), profile = DiaryProfile(name: "Synthetic lifter", timeZoneID: "Asia/Jerusalem")
        _ = try await store.createProfile(profile)
        let session = try await store.startWorkout(WorkoutDraft(kind: .strength, durationMinutes: 0, exercises: [], activity: "strength"),
                                                   at: Date(timeIntervalSince1970: 1_800_000_000), expectedProfileID: profile.id)
        let model = LiveWorkoutModel(store: store, profileID: profile.id, session: session, unit: "kg", mode: .live)

        // The best guess is added at once, so closing the choice sheet keeps it.
        await model.addGuess(MachineGuess(best: "seated-cable-row", options: ["seated-cable-row", "face-pull"]))
        #expect(model.session.exercises.map(\.exerciseID) == ["seated-cable-row"])
        #expect(model.pendingGuess?.exercise == 0 && model.pendingGuess?.options == ["seated-cable-row", "face-pull"])
        #expect(try await store.activeWorkout(expectedProfileID: profile.id)?.exercises.map(\.exerciseID) == ["seated-cable-row"])

        // Choosing another option swaps it in place; the choice is then settled.
        await model.chooseGuess("face-pull")
        #expect(model.session.exercises.map(\.exerciseID) == ["face-pull"])
        #expect(model.pendingGuess == nil)

        // A one-option guess has nothing to change; the first tick also settles an open guess.
        await model.addGuess(MachineGuess(best: "leg-press", options: ["leg-press"]))
        #expect(model.pendingGuess == nil)
        await model.addGuess(MachineGuess(best: "hack-squat", options: ["hack-squat", "smith-machine-squat"]))
        #expect(model.pendingGuess?.exercise == 2)
        await model.tick(exercise: 2, set: 0)
        #expect(model.pendingGuess == nil)
    }
}
