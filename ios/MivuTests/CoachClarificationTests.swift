import Foundation
import Testing
@testable import Mivu

private actor Replies {
    var results: [CoachInferenceResult]
    init(_ results: [CoachInferenceResult]) { self.results = results }
    func infer(_ input: [CoachInferenceInput], _ tools: Data) throws -> CoachInferenceResult {
        guard !results.isEmpty else { throw CoachError.limitExceeded }
        return results.removeFirst()
    }
}

@Suite @MainActor struct CoachClarificationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func fixture() async throws -> (DiaryStore, DiaryProfile, URL) {
        let root = URL.temporaryDirectory.appending(path: "CoachClarification-" + UUID().uuidString)
        let clock = now
        let store = DiaryStore(directory: root, currentTime: { clock }); let profile = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); _ = try await store.startDay(at: now)
        return (store, profile, root)
    }
    private func log(_ store: DiaryStore, _ profile: DiaryProfile, _ name: String) async throws -> CoachReceipt {
        let turn = try await capturedTurn(store, text: "Ate " + name, photos: [], at: now, expectedProfileID: profile.id)
        let item = FoodItem(name: name, quantity: 1, unit: "portion", nutrition: NutritionValues(kcal: 100), provenance: .estimate, reference: "Synthetic estimate")
        return try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2027-01-15", items: [item], expectedProfileID: profile.id)
    }
    private func call(_ name: String, _ args: String, id: String = "call1") -> CoachToolCall {
        CoachToolCall(id: id, callID: id, name: name, namespace: "mivu", arguments: args)
    }
    private func result(_ calls: [CoachToolCall] = [], text: String = "") -> CoachInferenceResult {
        CoachInferenceResult(model: "fixture", text: text, calls: calls, outputItems: [])
    }
    private func run(_ store: DiaryStore, _ profile: DiaryProfile, _ turn: CoachTurn, _ results: [CoachInferenceResult]) async throws -> CoachTurnResult {
        let replies = Replies(results)
        return try await CoachEngine(store: store, infer: { try await replies.infer($0, $1) }).run(turnID: turn.id, expectedProfileID: profile.id)
    }

    @Test func candidatesPersistAndFeedNextTurn() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let eggs = try #require(try await log(store, profile, "Eggs").mealID), soup = try #require(try await log(store, profile, "Soup").mealID)
        let turn = try await capturedTurn(store, text: "Make that bigger", photos: [], at: now, expectedProfileID: profile.id)
        let args = #"{"kind":"meal","candidates":[{"meal_id":"\#(eggs)"},{"meal_id":"\#(soup)","item_id":null}]}"#
        let finished = try await run(store, profile, turn, [result([call("ask_clarification", args)])])
        #expect(finished.state == .completed && finished.assistantText == "Which one did you mean?")
        let stored = try await exportedTurn(store, turnID: turn.id, expectedProfileID: profile.id)
        #expect(stored.question?.candidates == [.meal(mealID: eggs), .meal(mealID: soup)] && stored.question?.kind == .meal)
        let next = try await capturedTurn(store, text: "The soup", photos: [], at: now.addingTimeInterval(60), expectedProfileID: profile.id)
        let pending = try #require(await store.coachContext(turnID: next.id, expectedProfileID: profile.id).focus?.pendingQuestion)
        #expect(pending.originalText == "Make that bigger" && pending.candidates.count == 2)
        let page = try await store.coachPage(.latest, expectedProfileID: profile.id)
        #expect(page.exchanges.first { $0.id == turn.id }?.question == stored.question)
    }

    @Test func confirmUsesMealName() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let meal = try #require(try await log(store, profile, "Snickers Minis").mealID)
        let turn = try await capturedTurn(store, text: "Delete the snickers", photos: [], at: now, expectedProfileID: profile.id)
        let finished = try await run(store, profile, turn, [result([call("ask_clarification", #"{"kind":"confirm","candidates":[{"meal_id":"\#(meal)"}]}"#)])])
        #expect(finished.assistantText == "Remove the whole Snickers Minis meal?")
    }

    @Test func unknownCandidateRejected() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await capturedTurn(store, text: "Make that bigger", photos: [], at: now, expectedProfileID: profile.id)
        await #expect(throws: CoachError.limitExceeded) {
            _ = try await run(store, profile, turn, [result([call("ask_clarification", #"{"kind":"meal","candidates":[{"meal_id":"\#(UUID())"}]}"#)])])
        }
        let meal = CoachContext.Meal(id: UUID(), dayID: UUID(), revision: 1, eatenAt: now, timePrecision: .dateOnly, items: [FoodItem(name: "Eggs", nutrition: NutritionValues(kcal: 100))])
        for args in [#"{"kind":"meal","candidates":[{"meal_id":"\#(meal.id)","item_id":"\#(UUID())"}]}"#,   // item not in meal
                     #"{"kind":"confirm"}"#,
                     #"{"kind":"meal","candidates":[{"meal_id":"\#(meal.id)"},{"meal_id":"\#(meal.id)"},{"meal_id":"\#(meal.id)"},{"meal_id":"\#(meal.id)"},{"meal_id":"\#(meal.id)"}]}"#] {
            #expect(throws: CoachError.invalidArguments) { try CoachTools.parse(call("ask_clarification", args), meals: [meal], evidence: [:], receipts: []) }
        }
    }

    @Test func foundMealsAreCandidatesAndConfirmItemMeansItsMeal() throws {
        let item = CoachMealCandidate.Item(id: UUID(), name: "Pizza slice", quantity: 1, unit: "slice")
        let found = CoachMealCandidate(id: UUID(), dayID: UUID(), localDate: "2027-01-01", timeZoneID: "UTC", revision: 1, eatenAt: now, timePrecision: .dateOnly,
            items: [item], omittedItemCount: 0, capturedDescription: "Pizza", descriptionTruncated: false)
        let pick = #"{"kind":"meal","candidates":[{"meal_id":"\#(found.id)","item_id":"\#(item.id)"}]}"#
        guard case .clarification(_, let candidates) = try CoachTools.parse(call("ask_clarification", pick), meals: [], evidence: [:], receipts: [], found: [found]) else { Issue.record("must parse"); return }
        #expect(candidates == [.item(mealID: found.id, itemID: item.id)])
        let confirm = #"{"kind":"confirm","candidates":[{"meal_id":"\#(found.id)","item_id":"\#(item.id)"}]}"#
        guard case .clarification(.confirm, let target) = try CoachTools.parse(call("ask_clarification", confirm), meals: [], evidence: [:], receipts: [], found: [found]) else { Issue.record("must parse"); return }
        #expect(target == [.meal(mealID: found.id)])
    }

    @Test func confirmItemCandidateAsksAboutItsMeal() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let receipt = try await log(store, profile, "Snickers Minis")
        let meal = try #require(receipt.mealID), item = try #require(try await store.coachMeal(id: meal, expectedProfileID: profile.id).items.first?.id)
        let turn = try await capturedTurn(store, text: "Delete the snickers", photos: [], at: now, expectedProfileID: profile.id)
        let finished = try await run(store, profile, turn, [result([call("find_meals", #"{"query":"snickers"}"#, id: "f")]),
            result([call("ask_clarification", #"{"kind":"confirm","candidates":[{"meal_id":"\#(meal)","item_id":"\#(item)"}]}"#)])])
        #expect(finished.assistantText == "Remove the whole Snickers Minis meal?")
        #expect(try await exportedTurn(store, turnID: turn.id, expectedProfileID: profile.id).question?.candidates == [.meal(mealID: meal)])
    }

    @Test func clarificationAfterWriteCompletes() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await capturedTurn(store, text: "Eggs and then something", photos: [], at: now, expectedProfileID: profile.id)
        let log = #"{"target_local_date":"2027-01-15","items":[{"name":"Eggs","quantity":2,"unit":"egg","kcal":140,"carbs":1,"protein":12,"fat":10}]}"#
        let finished = try await run(store, profile, turn, [result([call("log_food", log)]), result([call("ask_clarification", #"{"kind":"portion"}"#, id: "q")])])
        let question = CoachClarification.portion.question
        #expect(finished.state == .completed && finished.receipts.count == 1)
        #expect(finished.assistantText?.contains("140") == true && finished.assistantText?.hasSuffix("\n" + question) == true)
    }

    @Test func deletedCandidateReplyIsUnavailable() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let meal = try #require(try await log(store, profile, "Eggs").mealID)
        try await store.deleteMeal(meal, expectedProfileID: profile.id)
        let prepared = try await store.coachCapturePreparation(at: now, expectedProfileID: profile.id)
        let id = UUID()
        let payload = try CoachSubmissionPayload(submissionID: id, text: "That one", attachments: [], context: prepared.context, reply: CoachReply(target: .meal(mealID: meal), excerpt: "Eggs"))
        _ = try await store.captureCoachSubmission(payload, expectedSelection: prepared.ownership, expectedProfileID: profile.id)
        #expect(try await store.coachContext(turnID: id, expectedProfileID: profile.id).replyTo?.unavailable == true)
    }
}
