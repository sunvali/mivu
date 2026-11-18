import Foundation
import Testing
@testable import Mivu

@Suite struct RecentMealsTests {
    /// One saved oats meal a day on 2027-03-01...04 (eaten at 8:00 and 19:00), plus an unsaved meal on 03-03.
    private func fixture() throws -> (CaptureFixture, [String: [UUID]], UUID) {
        var source = ChatHistoryFixture.lunchCorrectionSnapshot()
        var ids: [String: [UUID]] = [:]
        let template = source.meals[0]
        var unsavedID = UUID()
        for day in 1...4 {
            let label = String(format: "2027-03-%02d", day)
            let startAt = Date(timeIntervalSince1970: 1_835_000_000 + Double(day) * 86_400)
            let tracking = TrackingDay(id: UUID(), localDate: label, timeZoneID: "UTC", startAt: startAt)
            source.days.append(tracking)
            for hours in [8.0, 19.0] {
                var meal = template
                meal.id = UUID(); meal.dayID = tracking.id; meal.eatenAt = startAt.addingTimeInterval(hours * 3600)
                meal.photos = []; meal.submissions = [MealSubmission(id: UUID(), baseRevision: 0, text: "Synthetic oats", photoIDs: [], reviewFirst: false, state: .saved)]
                meal.items = [FoodItem(id: UUID(), name: "Oats", quantity: 1, unit: "bowl", nutrition: NutritionValues(kcal: 300))]
                source.meals.append(meal); ids[label, default: []].append(meal.id)
            }
            if day == 3 {
                var unsaved = template
                unsaved.id = UUID(); unsaved.dayID = tracking.id; unsaved.revision = 0; unsaved.eatenAt = startAt.addingTimeInterval(12 * 3600)
                unsaved.photos = []; unsaved.items = []
                unsaved.submissions = [MealSubmission(id: UUID(), baseRevision: 0, text: "Synthetic pending", photoIDs: [], reviewFirst: false, state: .captured)]
                source.meals.append(unsaved); unsavedID = unsaved.id
            }
        }
        return (try CaptureFixture(snapshot: source), ids, unsavedID)
    }

    @Test func recentMealsAreSavedOnlyNewestFirstAndInRange() async throws {
        let (f, ids, unsavedID) = try fixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root); _ = try await store.selectPagedProfile(f.profileID)
        let found = try await store.recentMeals(from: "2027-03-02", to: "2027-03-03", expectedProfileID: f.profileID)
        #expect(found.map(\.meal.id) == ids["2027-03-03"]!.reversed() + ids["2027-03-02"]!.reversed())
        #expect(found.map(\.localDate) == ["2027-03-03", "2027-03-03", "2027-03-02", "2027-03-02"])
        #expect(!found.map(\.meal.id).contains(unsavedID))
        #expect(found.allSatisfy { $0.meal.items.first?.name == "Oats" })
    }

    @Test func recentMealsRejectBadDatesAndAnotherProfile() async throws {
        let (f, _, _) = try fixture(); defer { f.remove() }
        let store = DiaryStore(directory: f.root); _ = try await store.selectPagedProfile(f.profileID)
        await #expect(throws: DiaryError.invalidData) { try await store.recentMeals(from: "2027-02-30", to: "2027-03-03", expectedProfileID: f.profileID) }
        await #expect(throws: DiaryError.wrongOwner) { try await store.recentMeals(from: "2027-03-01", to: "2027-03-03", expectedProfileID: UUID()) }
    }
}
