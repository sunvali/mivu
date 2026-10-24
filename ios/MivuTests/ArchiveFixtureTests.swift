import Foundation
import Testing
@testable import Mivu

/// Golden archives for other readers of `mivu-diary`; set MIVU_WRITE_FIXTURES=1 to regenerate them.
struct ArchiveFixtureTests {
    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/archive")

    private static func id(_ value: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))! }
    private static func at(_ offset: Double) -> Date { Date(timeIntervalSinceReferenceDate: 800_000_000 + offset) }

    static func syntheticFullSnapshot() throws -> DiarySnapshot {
        let profile = DiaryProfile(id: id(1), name: "Synthetic Profile", language: "en", timeZoneID: "Asia/Jerusalem",
            preferences: "Synthetic preferences", about: ProfileAbout(heightCm: 170.5, birthYear: 1990, sex: .female,
                pace: .gentle, dietTags: ["synthetic-tag"], healthNotes: "Synthetic note"))
        let days = DayCompleteness.allCases.enumerated().map { index, completeness in
            TrackingDay(id: id(10 + index), localDate: "2026-10-1\(index + 1)", timeZoneID: index == 0 ? "UTC" : "Asia/Jerusalem",
                startAt: at(Double(index) * 86_400), completeness: completeness, closedAt: index == 1 ? at(86_400 + 3_600.5) : nil)
        }
        let photos = PhotoRole.allCases.enumerated().map { index, role in
            MealPhoto(id: id(30 + index), data: Data([1, 2, 3]), createdAt: at(60 + Double(index)), role: role)
        }
        let items = [NutritionProvenance.sample, .user, .confirmedLabel, .identifiedSource, .estimate].enumerated().map { index, provenance in
            FoodItem(id: id(40 + index), name: "Synthetic food \(index)", quantity: 1.5, unit: "g",
                nutrition: NutritionValues(kcal: 100, carbs: index == 0 ? nil : 10.25, protein: 5, fat: 0),
                provenance: provenance, reference: "Synthetic reference", uncertain: index.isMultiple(of: 2),
                nutrientSources: ["kcal": provenance], nutritionBasis: index == 1 ? NutritionValues(kcal: 50, protein: 2.5) : nil,
                estimatedBy: index == 2 ? "apple-intelligence" : nil)
        }
        let states: [SubmissionState] = [.captured, .waitingForConnection, .analyzing, .awaitingReview, .saved, .needsRetry, .cancelled]
        let submissions = states.enumerated().map { index, state in
            MealSubmission(id: id(50 + index), baseRevision: index == 4 ? 1 : 0, text: "Synthetic submission \(index)",
                photoIDs: index == 0 ? photos.map(\.id) : [], reviewFirst: state == .awaitingReview, state: state,
                proposal: state == .awaitingReview ? AnalysisOutput(profileID: profile.id, mealID: id(20),
                    submissionID: id(50 + index), baseRevision: 0, items: [items[4]]) : nil)
        }
        var meals = [DiaryMeal(id: id(20), dayID: days[0].id, capturedAt: at(60), eatenAt: at(30), revision: 2, changedRevision: 5,
            timePrecision: .exact, items: items, photos: photos, submissions: submissions)]
        let targets: [ManualNutritionTarget] = [
            .recorded(dayID: days[0].id, localDate: days[0].localDate, timeZoneID: days[0].timeZoneID),
            .active(dayID: days[1].id, localDate: days[1].localDate, timeZoneID: days[1].timeZoneID, confirmPrevious: true),
            .newCurrent(dayID: days[2].id, localDate: days[2].localDate, timeZoneID: days[2].timeZoneID, previousActiveDayID: days[1].id),
        ]
        for (index, target) in targets.enumerated() {
            let append = index == 1
            let item = FoodItem(id: id(60 + index), name: "Synthetic manual \(index)", quantity: 2, unit: "cup",
                nutrition: NutritionValues(kcal: 0, protein: 1.25), provenance: .user, reference: "Entered", uncertain: false)
            let payload = ManualNutritionPayload(profileID: profile.id, mealID: id(21 + index), submissionID: id(70 + index),
                operation: append ? .append : .create, target: target, capturedAt: at(200 + Double(index)),
                eatenAt: at(100 + Double(index)), timePrecision: index == 2 ? .dateOnly : .exact,
                expectedMealRevision: append ? 1 : nil, items: [item])
            let base = append ? 1 : 0
            meals.append(DiaryMeal(id: payload.mealID, dayID: target.day.id, capturedAt: payload.capturedAt, eatenAt: payload.eatenAt,
                revision: base + 1, changedRevision: append ? nil : 6, timePrecision: payload.timePrecision, items: [item],
                submissions: [MealSubmission(id: payload.submissionID, baseRevision: base, text: "Synthetic manual", photoIDs: [],
                    reviewFirst: false, state: .saved, proposal: AnalysisOutput(profileID: profile.id, mealID: payload.mealID,
                        submissionID: payload.submissionID, baseRevision: base, items: [item]),
                    manualAcceptance: try ManualNutritionAcceptance(payload: payload))]))
        }
        let weights = [
            WeightEntry(id: id(80), dayID: nil, measuredAt: at(10), value: 70.5),
            WeightEntry(id: id(81), dayID: days[1].id, measuredAt: at(86_410), value: 155, unit: "lb", revision: 3, timePrecision: .dateOnly),
        ]
        let goal = GoalRecord(id: id(85), effectiveLocalDate: days[0].localDate, timeZoneID: "Asia/Jerusalem", revision: 2,
            targets: NutritionValues(kcal: 2000, protein: 120), goalWeightKg: 68, exerciseCreditEnabled: true)
        let workouts = [
            WorkoutSession(id: id(90), dayID: days[0].id, performedAt: at(500), timePrecision: .exact, revision: 1, kind: .strength,
                durationMinutes: 45, exercises: [WorkoutExercise(name: "Synthetic squat", sets: [WorkoutSet(repetitions: 8, loadKg: 60.5),
                    WorkoutSet(repetitions: 10, loadKg: nil)])], estimatedBurnKcal: 250, burnSource: .userEstimate),
            WorkoutSession(id: id(91), dayID: days[1].id, performedAt: at(86_500), timePrecision: .dateOnly, revision: 2, kind: .cardio,
                durationMinutes: 30, exercises: [], estimatedBurnKcal: 300.5, burnSource: .modelEstimate),
            WorkoutSession(id: id(92), dayID: days[2].id, performedAt: at(172_900), timePrecision: .exact, revision: 1, kind: .other,
                durationMinutes: 1, exercises: [], estimatedBurnKcal: nil, burnSource: nil),
        ]
        let coachPhoto = MealPhoto(id: id(100), data: Data([4, 5, 6]), createdAt: at(300), role: .before)
        let replyTargets: [CoachReply.Target] = [.message(turnID: id(111), fromPip: true), .meal(mealID: id(20)),
            .item(mealID: id(20), itemID: items[0].id), .day(dayID: days[0].id), .weight(weightID: weights[1].id),
            .workout(workoutID: workouts[0].id)]
        let text = "Synthetic coach message"
        let context = CoachCaptureContext(capturedAt: at(310), timeZoneID: "Asia/Jerusalem", activeDayID: days[1].id,
            previousDayConfirmedAt: at(305), activeConversationSegmentID: id(130))
        let manifest = try CoachSubmissionPayload(submissionID: id(110), text: text, attachments: [coachPhoto], context: context,
            reply: CoachReply(target: replyTargets[0], excerpt: "Synthetic excerpt")).manifest
        func receipt(_ key: String, revision: Int = 7) -> CoachReceipt {
            CoachReceipt(operationKey: "\(id(110).uuidString)/\(key)", turnID: id(110), dayID: days[0].id, committedRevision: revision, resultJSON: "{\"ok\":true}")
        }
        var receipts = [receipt("log_food"), receipt("correct_item"), receipt("weight"), receipt("workout"), receipt("goal")]
        receipts[0].mealID = id(20); receipts[0].commandFingerprint = String(repeating: "ab", count: 32)
        receipts[1].mealID = id(20); receipts[1].itemID = items[0].id
        receipts[2].weightID = weights[1].id
        receipts[3].workoutID = workouts[0].id
        receipts[4].dayID = nil; receipts[4].goalID = goal.id
        receipts += CoachDestination.allCases.map { destination in
            var value = receipt("open/\(destination.rawValue)", revision: 12); value.dayID = nil; value.destination = destination; return value
        }
        let main = CoachTurn(id: id(110), capturedAt: context.capturedAt, text: text, photos: [coachPhoto], state: .completed,
            assistantText: "Synthetic reply", receipts: receipts, captureTimeZoneID: context.timeZoneID, activeDayID: days[1].id,
            photoIDs: [coachPhoto.id, photos[0].id], needsDayChoice: false, resolvedDayID: days[0].id, submissionManifest: manifest,
            captureSegmentID: id(130), question: CoachQuestion(kind: .portion, candidates: replyTargets, originalText: "Synthetic question"),
            incomplete: true)
        let otherStates: [CoachTurnState] = [.captured, .analyzing, .waitingForConnection, .waitingForNetwork, .needsRetry, .needsClarification]
        let others = otherStates.enumerated().map { index, state in
            CoachTurn(id: id(111 + index), capturedAt: at(320 + Double(index)), text: "Synthetic turn \(index)", state: state,
                captureTimeZoneID: "UTC", pendingMealID: index == 1 ? id(20) : nil, pendingMealRevision: index == 1 ? 2 : nil,
                question: state == .needsClarification ? CoachQuestion(kind: CoachClarification.allCases[1], candidates: [], originalText: "Synthetic") : nil)
        }
        var snapshot = DiarySnapshot(revision: 12, profile: profile, days: days, meals: meals, weights: weights, goals: [goal],
            workouts: workouts, coachTurns: [main] + others, activeDayID: days[1].id, previousDayConfirmedAt: at(305),
            deletedMealIDs: [id(900)], deletedWeightIDs: [id(901)], deletedWorkoutIDs: [id(902)], lineage: [id(950), id(951)],
            activeConversationSegmentID: id(130))
        // Remaining clarification kinds ride on completed history so every case is archived.
        for kind in CoachClarification.allCases.dropFirst(2) {
            let index = snapshot.coachTurns.count
            snapshot.coachTurns.append(CoachTurn(id: id(111 + index), capturedAt: at(400 + Double(index)), text: "Synthetic \(kind.rawValue)",
                state: .completed, captureTimeZoneID: "UTC", question: CoachQuestion(kind: kind, candidates: [replyTargets[3]], originalText: "Synthetic")))
        }
        return snapshot
    }

    /// Older envelopes carry no verified manual acceptance; v1 and v2 also predate progress and Coach keys.
    static func projection(_ snapshot: DiarySnapshot, version: Int) -> DiarySnapshot {
        var value = snapshot
        for meal in value.meals.indices {
            for submission in value.meals[meal].submissions.indices { value.meals[meal].submissions[submission].manualAcceptance = nil }
        }
        guard version < 3 else { return value }
        value.goals = []; value.workouts = []; value.coachTurns = []; value.deletedWeightIDs = []; value.deletedWorkoutIDs = []
        for weight in value.weights.indices { value.weights[weight].revision = 1; value.weights[weight].timePrecision = .exact }
        return value
    }

    /// The app encoder's envelope at `version`, with sorted keys so regeneration is byte-stable.
    static func envelope(_ archive: Data, version: Int) throws -> Data {
        var envelope = try #require(JSONSerialization.jsonObject(with: archive) as? [String: Any])
        var body = try #require(envelope["snapshot"] as? [String: Any])
        if version < 4 {
            var meals = try #require(body["meals"] as? [[String: Any]])
            for meal in meals.indices {
                var submissions = try #require(meals[meal]["submissions"] as? [[String: Any]])
                for submission in submissions.indices { submissions[submission].removeValue(forKey: "manualAcceptance") }
                meals[meal]["submissions"] = submissions
            }
            body["meals"] = meals
        }
        if version < 3 {
            for key in ["goals", "workouts", "coachTurns", "deletedWeightIDs", "deletedWorkoutIDs"] { body.removeValue(forKey: key) }
            var weights = try #require(body["weights"] as? [[String: Any]])
            for weight in weights.indices { weights[weight].removeValue(forKey: "revision"); weights[weight].removeValue(forKey: "timePrecision") }
            body["weights"] = weights
        }
        envelope["snapshot"] = body; envelope["version"] = version
        return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }

    private static func name(_ version: Int) -> String { version == 4 ? "ios-v4-full.json" : "ios-v\(version).json" }

    @Test func fixturesMatchSyntheticSnapshot() throws {
        let snapshot = try Self.syntheticFullSnapshot()
        let full = try DiaryArchive.encode(snapshot)
        if ProcessInfo.processInfo.environment["MIVU_WRITE_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            for version in 1...4 {
                try (Self.envelope(full, version: version) + Data("\n".utf8)).write(to: Self.directory.appendingPathComponent(Self.name(version)))
            }
        }
        for version in 1...4 {
            let decoded = try DiaryArchive.decode(Data(contentsOf: Self.directory.appendingPathComponent(Self.name(version))))
            #expect(decoded == (version == 4 ? snapshot : Self.projection(snapshot, version: version)))
        }
    }
}
