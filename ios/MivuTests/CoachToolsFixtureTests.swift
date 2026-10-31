import Foundation
import Testing
@testable import Mivu

/// Golden Coach tool declarations and write fingerprints for other ports; set MIVU_WRITE_FIXTURES=1 to regenerate them.
struct CoachToolsFixtureTests {
    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/coach")

    private static func id(_ value: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))! }
    private static func at(_ offset: Double) -> Date { Date(timeIntervalSinceReferenceDate: 800_000_000 + offset) }

    struct Case: Codable, Equatable { var tool: String; var arguments: String; var target: String; var fingerprint: String }
    struct Fingerprints: Codable, Equatable { var meals: [CoachContext.Meal]; var workouts: [WorkoutSession]; var cases: [Case] }

    static func food(_ id: Int, _ name: String, _ quantity: Double, _ unit: String, _ nutrition: NutritionValues) -> FoodItem {
        FoodItem(id: Self.id(id), name: name, quantity: quantity, unit: unit, nutrition: nutrition, provenance: .estimate,
            reference: "Synthetic reference", uncertain: true)
    }

    static func fingerprints() throws -> Fingerprints {
        let meal = CoachContext.Meal(id: id(20), dayID: id(10), revision: 3, eatenAt: at(30), timePrecision: .dateOnly,
            items: [food(41, "Synthetic oats", 40, "g", NutritionValues(kcal: 150.5, carbs: 27, protein: 5, fat: 2.5)),
                    food(42, "Synthetic milk", 200, "ml", NutritionValues(kcal: 100, carbs: 9.6, protein: 6.8, fat: 3.2))],
            photos: [.init(id: id(30), role: .unspecified)],
            review: .init(submissionID: id(50), baseRevision: 3, items: [food(43, "Synthetic banana", 1, "medium", NutritionValues(kcal: 105))]))
        let workout = WorkoutSession(id: id(90), dayID: id(10), performedAt: at(500), timePrecision: .dateOnly, revision: 2,
            kind: .strength, durationMinutes: 45, exercises: [], estimatedBurnKcal: nil, burnSource: nil)
        let m = id(20).uuidString, w = id(90).uuidString, weight = id(80).uuidString
        let calls: [(String, String)] = [
            ("log_food", #"{"target_local_date":"2026-10-24","items":[{"name":"Synthetic rice/beans","quantity":150,"unit":"g","kcal":210.5,"carbs":null,"protein":4.25,"fat":0.1,"evidence_id":null}],"eaten_at":"2026-10-24T08:30:00Z","review_first":true}"#),
            ("log_food", #"{"target_local_date":"2026-10-24","items":[{"name":"Synthetic tea é","quantity":1,"unit":"cup","kcal":null,"carbs":null,"protein":null,"fat":null},{"name":"Synthetic toast","quantity":2.50,"unit":"slice","kcal":1e2,"carbs":30,"protein":6,"fat":2}],"eaten_at":null}"#),
            ("correct_item", #"{"meal_id":"\#(m)","item_id":"\#(id(41).uuidString)","expected_revision":3,"quantity":0.1}"#),
            ("log_weight", #"{"local_date":"2026-10-24","value":70.3,"unit":"kg","weight_id":null,"expected_revision":null,"measured_at":null}"#),
            ("log_weight", #"{"local_date":"2026-10-24","value":155.5,"unit":"lb","weight_id":"\#(weight)","expected_revision":2,"measured_at":"2026-10-24"}"#),
            ("log_workout", #"{"local_date":"2026-10-24","kind":"strength","duration_minutes":45,"exercises":[{"name":"Synthetic squat","sets":[{"repetitions":8,"load_kg":60.5},{"repetitions":10,"load_kg":null}]}],"estimated_burn_kcal":250,"burn_source":"userEstimate","performed_at":null}"#),
            ("edit_workout", #"{"workout_id":"\#(w)","expected_revision":2,"kind":"cardio","duration_minutes":30,"exercises":[],"estimated_burn_kcal":null,"burn_source":null,"performed_at":null}"#),
            ("delete_weight", #"{"weight_id":"\#(weight)","expected_revision":2}"#),
            ("delete_workout", #"{"workout_id":"\#(w)","expected_revision":2}"#),
            ("edit_item", #"{"meal_id":"\#(m)","expected_revision":3,"item_id":"\#(id(41).uuidString)","review_submission_id":null,"name":"Synthetic oats/bran","quantity":null,"unit":null,"nutrients":[{"nutrient":"protein","value":6.5},{"nutrient":"kcal","value":null}]}"#),
            ("edit_item", #"{"meal_id":"\#(m)","expected_revision":3,"item_id":"\#(id(43).uuidString)","review_submission_id":"\#(id(50).uuidString)","quantity":2}"#),
            ("append_food", #"{"meal_id":"\#(m)","expected_revision":3,"items":[{"name":"Synthetic honey","quantity":1,"unit":"tbsp","kcal":64,"carbs":17.3,"protein":0.1,"fat":0}]}"#),
            ("accept_review", #"{"meal_id":"\#(m)","expected_revision":3,"submission_id":"\#(id(50).uuidString)"}"#),
            ("move_meal", #"{"meal_id":"\#(m)","expected_revision":3,"target_local_date":"2026-10-23"}"#),
            ("delete_meal", #"{"meal_id":"\#(m)","expected_revision":3}"#),
            ("delete_item", #"{"meal_id":"\#(m)","expected_revision":3,"item_id":"\#(id(42).uuidString)"}"#),
            ("scale_meal", #"{"meal_id":"\#(m)","expected_revision":3,"target_kcal":650}"#),
            ("attach_photos", #"{"meal_id":"\#(m)","expected_revision":3,"photo_ids":["\#(id(32).uuidString)","\#(id(31).uuidString)"],"role":"after"}"#),
            ("delete_photo", #"{"meal_id":"\#(m)","expected_revision":3,"photo_id":"\#(id(30).uuidString)"}"#),
            ("retry_meal", #"{"meal_id":"\#(m)","expected_revision":0}"#),
            ("set_goals", #"{"effective_local_date":"2026-10-24","expected_revision":null,"targets":[{"nutrient":"protein","value":120},{"nutrient":"carbs","value":null}],"goal_weight_kg":68.2,"clear_goal_weight":false,"exercise_credit_enabled":true}"#),
            ("update_preferences", #"{"expected_diary_revision":12,"timezone":"Europe/London","preferences":"Synthetic: no peanuts \"really\""}"#),
            ("start_day", #"{"expected_diary_revision":12}"#),
            ("set_day_coverage", #"{"local_date":"2026-10-22","skipped":true}"#),
            ("undo_change", #"{"operation_key":"\#(id(110).uuidString)/food/2026-10-24"}"#),
            ("open_settings", #"{"destination":"backup"}"#),
        ]
        let cases = try calls.map { name, arguments -> Case in
            let call = CoachToolCall(id: name, callID: name, name: name, namespace: "mivu", arguments: arguments)
            guard case .write(let write) = try CoachTools.parse(call, meals: [meal], evidence: [:], receipts: [], workouts: [workout]) else {
                throw CoachError.invalidTool
            }
            return Case(tool: name, arguments: arguments, target: write.target, fingerprint: try write.commandFingerprint())
        }
        return Fingerprints(meals: [meal], workouts: [workout], cases: cases)
    }

    static func tools() throws -> Data {
        let object = try JSONSerialization.jsonObject(with: CoachTools.declarations())
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
    }

    @Test func fixturesMatchCurrentDeclarationsAndFingerprints() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let files = [("tools.json", try Self.tools()), ("fingerprints.json", try encoder.encode(Self.fingerprints()))]
        if ProcessInfo.processInfo.environment["MIVU_WRITE_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            for (name, data) in files { try (data + Data("\n".utf8)).write(to: Self.directory.appendingPathComponent(name)) }
        }
        for (name, data) in files {
            #expect(try Data(contentsOf: Self.directory.appendingPathComponent(name)) == data + Data("\n".utf8), "\(name) is stale")
        }
    }
}
