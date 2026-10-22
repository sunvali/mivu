import Foundation
import FoundationModels
import Testing
@testable import Mivu

struct AppleInferenceTests {
    @Test func appleResultsUseTheSharedReplayableItemShape() throws {
        guard #available(iOS 27.0, *) else { Issue.record("Apple inference requires iOS 27"); return }
        let calls = [Transcript.ToolCall(id: "a", toolName: "log_food", arguments: try GeneratedContent(json: #"{"target_local_date":"2026-10-23"}"#))]
        let result = try AppleInference.result(text: "", calls: calls)
        #expect(result.calls.map(\.callID) == ["a"] && result.calls.allSatisfy { $0.namespace == CoachTools.namespace && $0.name == "log_food" })
        let answer = try AppleInference.result(text: "Done.", calls: [])
        #expect(answer.calls.isEmpty && answer.text == "Done.")
        // CoachEngine replays these items next step, so they must pass the same validation as ChatGPT's.
        for item in result.outputItems + answer.outputItems { _ = try CoachInferenceInput.priorOutput(item).object() }
    }

    @Test @MainActor func appleAnswersWhenNoChatGPTPlanIsConnected() throws {
        guard #available(iOS 27.0, *) else { Issue.record("Apple inference requires iOS 27"); return }
        let apple = ChatGPTConnection(preferences: UserDefaults(suiteName: "AppleInference-" + UUID().uuidString)!, appleModelAvailable: { true })
        #expect(apple.provider == .apple)
        #expect(!apple.planAuthorized && apple.canInfer)
        #expect(throws: Never.self) { _ = try apple.inference() }
        let none = ChatGPTConnection(preferences: UserDefaults(suiteName: "AppleInference-" + UUID().uuidString)!, appleModelAvailable: { false })
        #expect(none.provider == .chatGPT)
        #expect(!none.canInfer)
        #expect(throws: SessionError.noActiveSession) { _ = try none.inference() }
    }

    @Test @MainActor func savedAppleChoiceUsesChatGPTWhileAppleIsUnavailable() throws {
        let preferences = UserDefaults(suiteName: "AppleInference-" + UUID().uuidString)!
        ChatGPTConnection(preferences: preferences, appleModelAvailable: { true }).provider = .apple
        let unavailable = ChatGPTConnection(preferences: preferences, appleModelAvailable: { false })
        #expect(unavailable.provider == .chatGPT)
        #expect(throws: SessionError.noActiveSession) { _ = try unavailable.inference() }
        #expect(ChatGPTConnection(preferences: preferences, appleModelAvailable: { true }).provider == .apple)
    }

    @Test @MainActor func chosenProviderPersistsAndChatGPTChoiceNeverFallsBackToApple() throws {
        let preferences = UserDefaults(suiteName: "AppleInference-" + UUID().uuidString)!
        let first = ChatGPTConnection(preferences: preferences, appleModelAvailable: { true })
        first.provider = .chatGPT
        let relaunched = ChatGPTConnection(preferences: preferences, appleModelAvailable: { true })
        #expect(relaunched.provider == .chatGPT)
        #expect(!relaunched.canInfer)
        #expect(throws: SessionError.noActiveSession) { _ = try relaunched.inference() }
    }

    @Test func localModelLogsANewMealThenCorrectsItsPortion() async throws {
        guard #available(iOS 27.0, *) else { Issue.record("Apple inference requires iOS 27"); return }
        let root = URL.temporaryDirectory.appending(path: "AppleLocal-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root); let profile = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); _ = try await store.startDay()
        let prompts = PromptLog()

        let log = try await capturedTurn(store, text: "Two boiled eggs", photos: [], expectedProfileID: profile.id)
        let logged = try await CoachEngine(store: store, infer: { input, tools in
            try await AppleInference.respondLocally(input, namespace: tools, pick: { _, _ in 0 }) { prompt in
                await prompts.append(prompt.text)
                return AppleInference.LocalTurn(intent: .log, foods: [.init(name: "Boiled egg", searchName: "Boiled egg", quantity: 2, unit: "egg", kcal: 155, carbs: 1, protein: 13, fat: 11, kcalPer100g: 155, carbsPer100g: 1, proteinPer100g: 13, fatPer100g: 11),
                                                                      .init(name: "Toast", searchName: "Toast", quantity: 1, unit: "slice", kcal: 80, carbs: 14, protein: 3, fat: 1, kcalPer100g: 265, carbsPer100g: 49, proteinPer100g: 9, fatPer100g: 3)],
                                                editFood: nil, editQuantity: nil)
            }
        }).run(turnID: log.id, expectedProfileID: profile.id)
        #expect(logged.state == .completed && logged.receipts.count == 1)
        var meals = try await store.snapshotForExport().meals
        // Toast is not named in the message, so the grounding check keeps it out.
        #expect(meals.count == 1 && meals.first?.items.map(\.name) == ["Boiled egg"] && meals.first?.items.first?.nutrition.kcal == 155)

        let edit = try await capturedTurn(store, text: "Actually it was 3 eggs", photos: [], expectedProfileID: profile.id)
        let edited = try await CoachEngine(store: store, infer: { input, tools in
            try await AppleInference.respondLocally(input, namespace: tools, pick: { _, _ in 0 }) { prompt in
                await prompts.append(prompt.text)
                return AppleInference.LocalTurn(intent: .edit, foods: [], editFood: "eggs", editQuantity: 3)
            }
        }).run(turnID: edit.id, expectedProfileID: profile.id)
        #expect(edited.state == .completed && edited.receipts.count == 1)
        meals = try await store.snapshotForExport().meals
        #expect(meals.count == 1 && meals.first?.items.first?.quantity == 3)
        let sent = await prompts.texts
        #expect(sent == ["Two boiled eggs", "Actually it was 3 eggs"], "One call per turn with only the message, so saved foods cannot be copied")
    }

    @Test func localWeighedAmountsUsePerHundredGramValues() async throws {
        guard #available(iOS 27.0, *) else { Issue.record("Apple inference requires iOS 27"); return }
        let root = URL.temporaryDirectory.appending(path: "AppleLocal-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root); let profile = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); _ = try await store.startDay()
        let turn = try await capturedTurn(store, text: "200g grilled chicken breast", photos: [], expectedProfileID: profile.id)
        _ = try await CoachEngine(store: store, infer: { input, tools in
            try await AppleInference.respondLocally(input, namespace: tools, pick: { _, _ in 0 }) { _ in
                // The serving total repeats the per-100 g figure, the mistake measured on-device.
                AppleInference.LocalTurn(intent: .edit, foods: [.init(name: "Grilled chicken breast", searchName: "Grilled chicken breast", quantity: 200, unit: "g", kcal: 165, carbs: 0, protein: 31, fat: 3.6,
                                                                       kcalPer100g: 165, carbsPer100g: 0, proteinPer100g: 31, fatPer100g: 3.6)],
                                         editFood: nil, editQuantity: nil)
            }
        }).run(turnID: turn.id, expectedProfileID: profile.id)
        let item = try #require(try await store.snapshotForExport().meals.first?.items.first)
        #expect(item.nutrition.kcal == 330 && item.nutrition.protein == 62)
    }

    @Test func localNutritionComesFromTheTableForSlicesAndWeighedAmounts() async throws {
        guard #available(iOS 27.0, *) else { Issue.record("Apple inference requires iOS 27"); return }
        let root = URL.temporaryDirectory.appending(path: "AppleLocal-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root); let profile = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); _ = try await store.startDay()
        let picks = PromptLog()
        let turn = try await capturedTurn(store, text: "2 slices of pepperoni pizza and 200g grilled chicken breast", photos: [], expectedProfileID: profile.id)
        // Model numbers are deliberately wrong: the saved values must come from the table.
        @Sendable func food(_ name: String, _ quantity: Double, _ unit: String) -> AppleInference.LocalTurn.Food {
            .init(name: name, searchName: name, quantity: quantity, unit: unit, kcal: 0, carbs: 0, protein: 0, fat: 0, kcalPer100g: 0, carbsPer100g: 0, proteinPer100g: 0, fatPer100g: 0)
        }
        _ = try await CoachEngine(store: store, infer: { input, tools in
            try await AppleInference.respondLocally(input, namespace: tools, pick: { phrase, options in
                await picks.append(phrase + " | " + options.map(\.description).joined(separator: " | "))
                let wanted = phrase.contains("pizza") ? "Pizza with pepperoni, stuffed crust" : "Chicken breast, grilled without sauce, skin eaten"
                return (options.firstIndex { $0.description == wanted } ?? -1) + 1
            }) { _ in
                AppleInference.LocalTurn(intent: .log, foods: [food("pepperoni pizza", 2, "slice"), food("grilled chicken breast", 200, "g")], editFood: nil, editQuantity: nil)
            }
        }).run(turnID: turn.id, expectedProfileID: profile.id)
        let items = try #require(try await store.snapshotForExport().meals.first?.items)
        // FNDDS: stuffed-crust pepperoni pizza 296 kcal/100 g, "1 piece, NFS" 164 g; grilled chicken breast 206 kcal/100 g.
        #expect(items.map(\.name) == ["pepperoni pizza", "grilled chicken breast"])
        #expect(items.map(\.quantity) == [2, 200] && items.map(\.unit) == ["slice", "g"])
        #expect(items.map(\.nutrition.kcal) == [970.9, 412])
        let sent = await picks.texts
        #expect(sent.count == 2 && sent.allSatisfy { $0.contains("Pizza with pepperoni, stuffed crust") || $0.contains("Chicken breast, grilled") })
        #expect(sent.first?.hasPrefix("2 slice pepperoni pizza |") == true)
    }

    @Test func localUnitWithoutAMatchingPortionKeepsTheModelEstimate() async throws {
        guard #available(iOS 27.0, *) else { Issue.record("Apple inference requires iOS 27"); return }
        let root = URL.temporaryDirectory.appending(path: "AppleLocal-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root); let profile = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); _ = try await store.startDay()
        let turn = try await capturedTurn(store, text: "a chocolate chip cookie", photos: [], expectedProfileID: profile.id)
        _ = try await CoachEngine(store: store, infer: { input, tools in
            try await AppleInference.respondLocally(input, namespace: tools, pick: { _, options in
                (options.firstIndex { $0.description == "Cookie, chocolate chip" } ?? -1) + 1
            }) { _ in
                // FNDDS has no "piece" portion for this cookie.
                AppleInference.LocalTurn(intent: .log, foods: [.init(name: "chocolate chip cookie", searchName: "chocolate chip cookie", quantity: 1, unit: "piece",
                                                                      kcal: 80, carbs: 10, protein: 1, fat: 4, kcalPer100g: 480, carbsPer100g: 62, proteinPer100g: 5, fatPer100g: 24)],
                                         editFood: nil, editQuantity: nil)
            }
        }).run(turnID: turn.id, expectedProfileID: profile.id)
        // Not the 60 g "Quantity not specified" serving (295 kcal), which measured worse than the model.
        #expect(try await store.snapshotForExport().meals.first?.items.first?.nutrition.kcal == 80)
    }

    @Test func localCaloriesNeverFallBelowWhatTheMacrosImply() async throws {
        guard #available(iOS 27.0, *) else { Issue.record("Apple inference requires iOS 27"); return }
        let root = URL.temporaryDirectory.appending(path: "AppleLocal-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root); let profile = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); _ = try await store.startDay()
        let turn = try await capturedTurn(store, text: "a can of coca cola", photos: [], expectedProfileID: profile.id)
        _ = try await CoachEngine(store: store, infer: { input, tools in
            try await AppleInference.respondLocally(input, namespace: tools, pick: { _, _ in 0 }) { _ in
                // Measured on-device: a regular Coke given a diet drink's 3 kcal beside its 35 g of sugar.
                AppleInference.LocalTurn(intent: .log, foods: [.init(name: "Coca cola", searchName: "Coca cola", quantity: 1, unit: "can", kcal: 3, carbs: 35, protein: 0, fat: 0,
                                                                      kcalPer100g: 1, carbsPer100g: 10.6, proteinPer100g: 0, fatPer100g: 0)],
                                         editFood: nil, editQuantity: nil)
            }
        }).run(turnID: turn.id, expectedProfileID: profile.id)
        #expect(try await store.snapshotForExport().meals.first?.items.first?.nutrition.kcal == 140)
    }

    @Test func localUnnamedEditChangesTheOnlyFoodInTheLatestMeal() async throws {
        guard #available(iOS 27.0, *) else { Issue.record("Apple inference requires iOS 27"); return }
        let root = URL.temporaryDirectory.appending(path: "AppleLocal-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root); let profile = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); _ = try await store.startDay()
        let log = try await capturedTurn(store, text: "coke zero", photos: [], expectedProfileID: profile.id)
        _ = try await CoachEngine(store: store, infer: { input, tools in
            try await AppleInference.respondLocally(input, namespace: tools, pick: { _, _ in 0 }) { _ in
                AppleInference.LocalTurn(intent: .log, foods: [.init(name: "coke zero", searchName: "diet cola", quantity: 1, unit: "can",
                                                                      kcal: 1, carbs: 0, protein: 0, fat: 0, kcalPer100g: 0, carbsPer100g: 0, proteinPer100g: 0, fatPer100g: 0)],
                                         editFood: nil, editQuantity: nil)
            }
        }).run(turnID: log.id, expectedProfileID: profile.id)
        // Measured on the owner's iPhone: "make it three" names no food.
        let edit = try await capturedTurn(store, text: "make it three", photos: [], expectedProfileID: profile.id)
        let edited = try await CoachEngine(store: store, infer: { input, tools in
            try await AppleInference.respondLocally(input, namespace: tools, pick: { _, _ in 0 }) { _ in
                AppleInference.LocalTurn(intent: .edit, foods: [], editFood: "chocolate", editQuantity: 3) // Measured on the owner's iPhone: an invented name.
            }
        }).run(turnID: edit.id, expectedProfileID: profile.id)
        #expect(edited.receipts.count == 1)
        #expect(try await store.snapshotForExport().meals.first?.items.first?.quantity == 3)

        // Measured live: after a second same-day meal, "make it 3" changed the older one (date-only times tie).
        let pizza = try await capturedTurn(store, text: "pepperoni pizza", photos: [], expectedProfileID: profile.id)
        _ = try await CoachEngine(store: store, infer: { input, tools in
            try await AppleInference.respondLocally(input, namespace: tools, pick: { _, _ in 0 }) { _ in
                AppleInference.LocalTurn(intent: .log, foods: [.init(name: "pepperoni pizza", searchName: "pepperoni pizza", quantity: 2, unit: "slice",
                                                                      kcal: 600, carbs: 70, protein: 25, fat: 25, kcalPer100g: 290, carbsPer100g: 34, proteinPer100g: 12, fatPer100g: 12)],
                                         editFood: nil, editQuantity: nil)
            }
        }).run(turnID: pizza.id, expectedProfileID: profile.id)
        let again = try await capturedTurn(store, text: "make it 4", photos: [], expectedProfileID: profile.id)
        _ = try await CoachEngine(store: store, infer: { input, tools in
            try await AppleInference.respondLocally(input, namespace: tools, pick: { _, _ in 0 }) { _ in
                AppleInference.LocalTurn(intent: .edit, foods: [], editFood: "ice cream", editQuantity: 4)
            }
        }).run(turnID: again.id, expectedProfileID: profile.id)
        let quantities = Dictionary(uniqueKeysWithValues: try await store.snapshotForExport().meals.flatMap(\.items).map { ($0.name, $0.quantity) })
        #expect(quantities == ["coke zero": 3, "pepperoni pizza": 4], "The last changed meal is what \"it\" means")
    }

    @Test func localTurnsStillWorkWhenAFoodNameContainsTheContextMarker() async throws {
        guard #available(iOS 27.0, *) else { Issue.record("Apple inference requires iOS 27"); return }
        let root = URL.temporaryDirectory.appending(path: "AppleLocal-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root); let profile = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); _ = try await store.startDay()
        @Sendable func food(_ name: String) -> AppleInference.LocalTurn.Food {
            .init(name: name, searchName: name, quantity: 1, unit: "bar", kcal: 200, carbs: 20, protein: 10, fat: 8, kcalPer100g: 400, carbsPer100g: 40, proteinPer100g: 20, fatPer100g: 16)
        }
        for (text, turn) in [("Context: protein bar", AppleInference.LocalTurn(intent: .log, foods: [food("Context: protein bar")], editFood: nil, editQuantity: nil)),
                             ("make it 2", AppleInference.LocalTurn(intent: .edit, foods: [], editFood: nil, editQuantity: 2))] {
            let captured = try await capturedTurn(store, text: text, photos: [], expectedProfileID: profile.id)
            // The second request's diary context contains the saved name, and with it the text "Context: ".
            let done = try await CoachEngine(store: store, infer: { input, tools in
                try await AppleInference.respondLocally(input, namespace: tools, pick: { _, _ in 0 }) { _ in turn }
            }).run(turnID: captured.id, expectedProfileID: profile.id)
            #expect(done.state == .completed, "\(text)")
        }
        #expect(try await store.snapshotForExport().meals.first?.items.first?.quantity == 2)
    }

    @Test func localEditOfAFoodNotInTheLatestMealChangesNothing() async throws {
        guard #available(iOS 27.0, *) else { Issue.record("Apple inference requires iOS 27"); return }
        let root = URL.temporaryDirectory.appending(path: "AppleLocal-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryStore(directory: root); let profile = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); _ = try await store.startDay()
        let log = try await capturedTurn(store, text: "Two boiled eggs", photos: [], expectedProfileID: profile.id)
        _ = try await CoachEngine(store: store, infer: { input, tools in
            try await AppleInference.respondLocally(input, namespace: tools, pick: { _, _ in 0 }) { _ in
                AppleInference.LocalTurn(intent: .log, foods: [.init(name: "Boiled egg", searchName: "Boiled egg", quantity: 2, unit: "egg", kcal: 155, carbs: 1, protein: 13, fat: 11, kcalPer100g: 155, carbsPer100g: 1, proteinPer100g: 13, fatPer100g: 11)], editFood: nil, editQuantity: nil)
            }
        }).run(turnID: log.id, expectedProfileID: profile.id)
        let edit = try await capturedTurn(store, text: "make the latte 2", photos: [], expectedProfileID: profile.id)
        let result = try await CoachEngine(store: store, infer: { input, tools in
            try await AppleInference.respondLocally(input, namespace: tools, pick: { _, _ in 0 }) { _ in AppleInference.LocalTurn(intent: .edit, foods: [], editFood: "latte", editQuantity: 2) }
        }).run(turnID: edit.id, expectedProfileID: profile.id)
        #expect(result.receipts.isEmpty)
        #expect(try await store.snapshotForExport().meals.first?.items.first?.quantity == 2)
    }
}

private actor PromptLog { var texts: [String] = []; func append(_ text: String) { texts.append(text) } }
