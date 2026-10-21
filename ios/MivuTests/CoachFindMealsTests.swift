import Foundation
import Testing
@testable import Mivu

@Suite struct CoachFindMealsTests {
    /// 12 synthetic pizza meals on 2027-03-01...12 (eaten at noon), plus the fixture's chicken lunches.
    private func fixture() throws -> (CaptureFixture, [String: UUID]) {
        var source = ChatHistoryFixture.lunchCorrectionSnapshot()
        var ids: [String: UUID] = [:]
        let template = source.meals[0]
        for day in 1...12 {
            let label = String(format: "2027-03-%02d", day)
            let startAt = Date(timeIntervalSince1970: 1_835_000_000 + Double(day) * 86_400)
            let tracking = TrackingDay(id: UUID(), localDate: label, timeZoneID: "UTC", startAt: startAt)
            var meal = template
            meal.id = UUID(); meal.dayID = tracking.id; meal.eatenAt = startAt.addingTimeInterval(43_200)
            meal.photos = []; meal.submissions = [MealSubmission(id: UUID(), baseRevision: 0, text: "Synthetic pizza", photoIDs: [], reviewFirst: false, state: .saved)]
            meal.items = [FoodItem(id: UUID(), name: day == 1 ? "100% PIZZA_slice" : "Pizza slice", quantity: 1, unit: "slice", nutrition: NutritionValues(kcal: 300))]
            source.days.append(tracking); source.meals.append(meal); ids[label] = meal.id
        }
        return (try CaptureFixture(snapshot: source), ids)
    }

    @Test func findsByNameNewestFirst() async throws {
        let (f, ids) = try fixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root); _ = try await store.selectPagedProfile(f.profileID)
        let found = try await store.coachFindMeals(query: "pIzZa", from: nil, to: nil, expectedProfileID: f.profileID)
        #expect(found.count == 10 && found.first?.id == ids["2027-03-12"] && found.last?.id == ids["2027-03-03"])
        #expect(found.map(\.eatenAt) == found.map(\.eatenAt).sorted(by: >))
        // % and _ are literal.
        let literal = try await store.coachFindMeals(query: "100% pizza_", from: nil, to: nil, expectedProfileID: f.profileID)
        #expect(literal.map(\.id) == [ids["2027-03-01"]!])
        #expect(try await store.coachFindMeals(query: "p_zza", from: nil, to: nil, expectedProfileID: f.profileID).isEmpty)
    }

    @Test func respectsDateRange() async throws {
        let (f, ids) = try fixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root); _ = try await store.selectPagedProfile(f.profileID)
        let found = try await store.coachFindMeals(query: "pizza", from: "2027-03-02", to: "2027-03-04", expectedProfileID: f.profileID)
        #expect(found.map(\.id) == [ids["2027-03-04"]!, ids["2027-03-03"]!, ids["2027-03-02"]!])
        await #expect(throws: DiaryError.invalidData) { try await store.coachFindMeals(query: "pizza", from: "2027-02-30", to: nil, expectedProfileID: f.profileID) }
        await #expect(throws: DiaryError.wrongOwner) { try await store.coachFindMeals(query: "pizza", from: nil, to: nil, expectedProfileID: UUID()) }
    }

    @Test func rejectsLongQuery() throws {
        func call(_ query: String) -> CoachToolCall {
            CoachToolCall(id: "f", callID: "f", name: "find_meals", namespace: "mivu",
                arguments: String(decoding: try! JSONSerialization.data(withJSONObject: ["query": query, "to_date": "2027-03-04"]), as: UTF8.self))
        }
        #expect(throws: CoachError.invalidArguments) { try CoachTools.parse(call(String(repeating: "a", count: 101)), meals: [], evidence: [:], receipts: []) }
        guard case .findMeals(let query, let from, let to) = try CoachTools.parse(call("pizza"), meals: [], evidence: [:], receipts: []) else { Issue.record("find_meals must parse"); return }
        #expect(query == "pizza" && from == nil && to == "2027-03-04")
    }
}
