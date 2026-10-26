import Foundation
import Testing
@testable import Mivu

struct FoodSourceTests {
    private func store() async throws -> (DiaryStore, DiaryProfile, URL) {
        let root = URL.temporaryDirectory.appending(path: "FoodSource-" + UUID().uuidString)
        let store = DiaryStore(directory: root); let profile = adultProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); _ = try await store.startDay()
        return (store, profile, root)
    }

    @Test func chatGPTFoodsRememberTheModelThatEstimatedThem() async throws {
        let (store, profile, root) = try await store(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await capturedTurn(store, text: "Two eggs", photos: [], expectedProfileID: profile.id)
        let date = try #require(try await store.coachContext(turnID: turn.id, expectedProfileID: profile.id).days.last?.localDate)
        let log = CoachToolCall(id: "c1", callID: "c1", name: "log_food", namespace: "mivu",
                                arguments: #"{"target_local_date":"\#(date)","items":[{"name":"Eggs","quantity":2,"unit":"egg","kcal":140,"carbs":1,"protein":12,"fat":10}]}"#)
        _ = try await CoachEngine(store: store, infer: { input, _ in
            let saved = input.contains { if case .functionOutput = $0 { true } else { false } }
            return CoachInferenceResult(model: "gpt-5.5", text: saved ? "Done" : "", calls: saved ? [] : [log], outputItems: [])
        }).run(turnID: turn.id, expectedProfileID: profile.id)
        let item = try #require(try await store.snapshotForExport().meals.first?.items.first)
        #expect(item.estimatedBy == "gpt-5.5" && item.estimatedByLabel == "ChatGPT")
        #expect(item.sourceCaption == "Estimated nutrition · ChatGPT")
        var edited = item; edited.provenance = .user
        #expect(edited.sourceCaption == "Edited by you", "A manual edit is not credited to the model")
    }

    @Test func appleFoodsAreLabelledAndOlderFoodsShowNoSource() async throws {
        guard #available(iOS 27.0, *) else { Issue.record("Apple inference requires iOS 27"); return }
        let (store, profile, root) = try await store(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await capturedTurn(store, text: "Two eggs", photos: [], expectedProfileID: profile.id)
        _ = try await CoachEngine(store: store, infer: { input, tools in
            try await AppleInference.respondLocally(input, namespace: tools, pick: { _, _ in 0 }) { _ in
                AppleInference.LocalTurn(intent: .log, foods: [.init(name: "eggs", searchName: "eggs", quantity: 2, unit: "egg", kcal: 140, carbs: 1, protein: 12, fat: 10,
                                                                      kcalPer100g: 155, carbsPer100g: 1, proteinPer100g: 13, fatPer100g: 11)],
                                         editFood: nil, editQuantity: nil)
            }
        }).run(turnID: turn.id, expectedProfileID: profile.id)
        #expect(try await store.snapshotForExport().meals.first?.items.first?.estimatedByLabel == "Apple Intelligence")
        #expect(FoodItem(name: "Older", nutrition: NutritionValues(kcal: 1)).estimatedByLabel == nil)
    }

    @Test func theSourceNeverChangesARetryFingerprint() throws {
        let item = FoodItem(name: "Eggs", nutrition: NutritionValues(kcal: 140), provenance: .estimate)
        var chatGPT = item; chatGPT.estimatedBy = "gpt-5.5"
        var apple = item; apple.estimatedBy = "apple-intelligence"
        // A turn half-saved by one model and retried by the other must still match its receipt.
        let fingerprints = try [item, chatGPT, apple].map { try CoachWrite.food(date: "2026-10-23", items: [$0], eatenAt: nil).commandFingerprint() }
        #expect(Set(fingerprints).count == 1)
    }
}
