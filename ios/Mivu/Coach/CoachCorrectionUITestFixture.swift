#if DEBUG
import CryptoKit
import Foundation
import Observation
import SQLite3
import SwiftUI

/// Synthetic-only controls around the existing transport. All diary writes retain the production writer.
enum CoachCorrectionUITestFixture {
    static var isEnabled: Bool {
        DiaryLaunch.isCoachInferenceFixture && DiaryLaunch.isCoachHistoryFixture && arguments.contains("--coach-correction-fixture")
    }
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }
    static var scenario: String {
        guard let index = arguments.firstIndex(of: "--correction-scenario"), arguments.indices.contains(index + 1) else { return "success" }
        return arguments[index + 1]
    }
    static var captureInstant: Date {
        ISO8601DateFormatter().date(from: scenario == "delayed" ? "2026-03-09T04:30:00Z" : "2027-01-16T10:00:00Z")!
    }
    static var processInstant: Date { captureInstant.addingTimeInterval(40 * 86_400) }
    static var captureZone: String { scenario == "delayed" ? "America/New_York" : "UTC" }
    static var targetDate: String { scenario == "delayed" ? "2026-03-08" : "2027-01-15" }
    static let phrase = "Please edit yesterday’s lunch because I ate one more chicken."
    static func id(_ value: Int) -> UUID { CoachUITestInference.historyID(value) }
    static var databaseURL: URL { DiaryLaunch.directory.appending(path: id(900).uuidString + ".sqlite/diary.sqlite") }

    @MainActor static func prepare(snapshot: inout DiarySnapshot) throws {
        guard isEnabled else { return }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: captureZone)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: captureInstant)!
        snapshot.profile.timeZoneID = captureZone
        snapshot.days[0].localDate = targetDate; snapshot.days[0].timeZoneID = captureZone
        snapshot.days[0].startAt = calendar.startOfDay(for: yesterday)
        snapshot.days[1].localDate = targetDate; snapshot.days[1].startAt = snapshot.days[0].startAt
        snapshot.meals[0].capturedAt = yesterday
        snapshot.meals[0].eatenAt = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: yesterday)!
        snapshot.meals[0].photos[0].createdAt = yesterday
        snapshot.meals[1].capturedAt = yesterday; snapshot.meals[1].eatenAt = snapshot.meals[0].eatenAt
        snapshot.coachTurns[0].capturedAt = yesterday; snapshot.coachTurns[0].activeDayID = id(901)
        snapshot.coachTurns[0].captureTimeZoneID = captureZone
        snapshot.coachTurns[0].receipts[0].operationKey = "\(id(1))/food/\(targetDate)"
        if scenario == "quantity" { snapshot.meals[0].items[0].quantity = 200; snapshot.meals[0].items[0].unit = "g" }
        if scenario == "item" {
            var chicken = snapshot.meals[0].items[0]; chicken.id = id(923); snapshot.meals[0].items.append(chicken)
        }
        if scenario == "description" {
            snapshot.meals[0].submissions[0].text = String(repeating: "Synthetic 🍎 ", count: 180) + "lunch"
            snapshot.coachTurns[0].text = snapshot.meals[0].submissions[0].text
        }
        if scenario == "meal" { snapshot.meals[1].submissions[0].text = "Another synthetic lunch" }
        if scenario == "page" {
            for index in 0..<21 {
                var meal = snapshot.meals[1]; meal.id = id(6000 + index)
                meal.submissions[0].id = id(6100 + index)
                meal.items = meal.items.enumerated().map { offset, item in var item = item; item.id = id(6200 + index * 3 + offset); return item }
                snapshot.meals.append(meal)
            }
        }
        if scenario == "itemsOmitted" {
            for index in 0..<196 {
                snapshot.meals[0].items.append(FoodItem(id: id(7000 + index), name: String(repeating: "Synthetic food ", count: 30), quantity: 1,
                    unit: "piece", nutrition: NutritionValues(kcal: 1), reference: String(repeating: "Source ", count: 250)))
            }
            var hidden = snapshot.meals[0].items[0]; hidden.id = id(7300); snapshot.meals[0].items.append(hidden)
        }
        // The target is outside both the 100-row window and the 14-day current-record context.
        for index in 0..<36 {
            let instant = calendar.date(byAdding: .day, value: index + 1, to: captureInstant)!
            let day = TrackingDay(id: id(8000 + index), localDate: diaryDateLabel(instant, zone: captureZone), timeZoneID: captureZone, startAt: instant)
            snapshot.days.append(day)
        }
        for index in 1..<snapshot.coachTurns.count {
            let day = snapshot.days[4 + min((index - 1) / 4, 35)]
            snapshot.coachTurns[index].capturedAt = day.startAt; snapshot.coachTurns[index].activeDayID = day.id
            snapshot.coachTurns[index].captureTimeZoneID = captureZone
        }
        snapshot.days[3].localDate = diaryDateLabel(processInstant, zone: captureZone)
        snapshot.days[3].startAt = processInstant; snapshot.days[3].timeZoneID = captureZone
        snapshot.previousDayConfirmedAt = processInstant
    }

    @MainActor static func installAudit() throws {
        guard isEnabled else { return }
        let database = try DiaryDatabase(url: databaseURL)
        try database.execute("CREATE TABLE IF NOT EXISTS correction_ui_audit(recordID TEXT, oldQuantity REAL, newQuantity REAL)")
        try database.execute("CREATE TRIGGER IF NOT EXISTS observe_ui_correction AFTER UPDATE ON item WHEN json_extract(CAST(NEW.payload AS TEXT), '$.quantity') != json_extract(CAST(OLD.payload AS TEXT), '$.quantity') BEGIN INSERT INTO correction_ui_audit VALUES (NEW.id, json_extract(CAST(OLD.payload AS TEXT), '$.quantity'), json_extract(CAST(NEW.payload AS TEXT), '$.quantity')); END")
    }

    @MainActor static func intercept(input: [CoachInferenceInput], context: CoachContext, result: CoachInferenceResult) async throws -> CoachInferenceResult {
        guard isEnabled else { return result }
        let runtime = CoachCorrectionFixtureState.shared
        runtime.contextMealIDs = context.meals.map { $0.id.uuidString }
        let outputs = input.compactMap { entry -> String? in if case .functionOutput(_, let value) = entry { return value }; return nil }
        runtime.calls += result.calls.map { ["name": $0.name, "arguments": $0.arguments] }
        if let first = outputs.first, let page = try? JSONDecoder().decode(CoachMealCandidatePage.self, from: Data(first.utf8)) {
            runtime.candidateMealIDs = page.meals.map { $0.id.uuidString }
        }
        if outputs.count >= 2, let meal = try? JSONDecoder().decode(CoachContext.Meal.self, from: Data(outputs[1].utf8)) {
            runtime.groundedMealID = meal.id.uuidString
            runtime.groundedItemIDs = meal.items.map { $0.id.uuidString }
            runtime.groundedQuantity = meal.items.first { $0.id == id(920) }?.quantity
        }
        // This boundary is reached only after Engine supplies the actual committed tool result.
        let committed = outputs.contains { output in
            guard let object = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any] else { return false }
            return object["item"] != nil && object["targetLocalDate"] != nil
        }
        if committed { runtime.observedCommitOutput = true }
        if scenario == "delayed", outputs.isEmpty { try await runtime.hold("before-processing") }
        if scenario == "stale", result.calls.contains(where: { $0.name == "correct_item" }) { try await runtime.hold("before-correction") }
        if ["crash", "crash-later-edit"].contains(scenario), committed { try await runtime.hold("after-commit") }
        runtime.phase = "running"
        return result
    }
}

@MainActor @Observable final class CoachCorrectionFixtureState {
    static let shared = CoachCorrectionFixtureState()
    var phase = "ready" { didSet { phaseGeneration &+= 1 } }
    private var phaseGeneration: UInt64 = 0
    private var refreshGeneration: UInt64 = 0
    var facts = "{}"
    var calls: [[String: String]] = []
    var contextMealIDs: [String] = []
    var observedCommitOutput = false
    var candidateMealIDs: [String] = []
    var groundedMealID = ""
    var groundedItemIDs: [String] = []
    var groundedQuantity: Double?
    private var releaseRequested = false
    private var expired = false
    private var baselineBusiness: String?
    private var baselineProtected: String?

    func hold(_ boundary: String) async throws {
        let key = "correction-ui-consumed-" + boundary
        guard !DiaryLaunch.defaults.bool(forKey: key) else { return }
        // Consume before suspension, so literal same-arguments process recovery cannot rearm the hold.
        DiaryLaunch.defaults.set(true, forKey: key)
        releaseRequested = false; phase = boundary
        let deadline = ContinuousClock.now.advanced(by: .seconds(45))
        while !releaseRequested {
            try Task.checkCancellation()
            if ContinuousClock.now >= deadline { expired = true; phase = "expired"; throw DiaryError.persistenceFailed }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    func release() { releaseRequested = true }

    func refresh(_ coach: CoachViewModel) async {
        guard let owner = coach.diary.selection else { return }
        refreshGeneration &+= 1
        let request = refreshGeneration
        var observedPhaseGeneration = phaseGeneration
        func isCurrent() -> Bool {
            request == refreshGeneration && coach.diary.selection == owner && !Task.isCancelled
        }
        do {
            try CoachCorrectionUITestFixture.installAudit()
            let store = coach.diary.store, profileID = owner.identity.profileID
            for _ in 0..<8 {
                guard isCurrent() else { return }
                let observedPhase = phase
                observedPhaseGeneration = phaseGeneration
                let before = try await store.diaryHead(expectedProfileID: profileID)
                let meal = try await store.meal(id: CoachCorrectionUITestFixture.id(910), expectedProfileID: profileID)
                let day = try await store.diaryDay(id: meal.dayID, expectedProfileID: profileID)
                let latest = try await store.coachLatestExchange(expectedSelection: owner)
                let accepted = latest?.text == CoachCorrectionUITestFixture.phrase ? latest : nil
                let chicken = meal.items.first { $0.id == CoachCorrectionUITestFixture.id(920) }
                let receipt = accepted?.receipts.first { $0.itemID == chicken?.id }
                let database = try DiaryDatabase(url: CoachCorrectionUITestFixture.databaseURL)
                let business = try digestRows(database, tables: ["meal", "item", "submission", "photo", "record_source", "photo_consumer"])
                let protected: [String: Any] = ["siblings": try json(Array(meal.items.filter { $0.id != chicken?.id })),
                    "capturedAt": meal.capturedAt.timeIntervalSince1970, "eatenAt": meal.eatenAt.timeIntervalSince1970,
                    "timePrecision": meal.timePrecision?.rawValue ?? "", "sourceTurnID": meal.sourceTurnID?.uuidString ?? "",
                    "photos": try json(meal.photos.map { PhotoFact(id: $0.photoID, role: $0.role, createdAt: $0.createdAt) }),
                    "basis": try json(chicken?.nutritionBasis), "reference": chicken?.reference ?? "",
                    "nutrientSources": try json(chicken?.nutrientSources), "unknownCarbs": chicken?.nutrition.carbs == nil]
                let protectedDigest = digest(try JSONSerialization.data(withJSONObject: protected, options: .sortedKeys))
                let audit = try rows(database, "SELECT recordID, oldQuantity, newQuantity FROM correction_ui_audit ORDER BY rowid")
                let chickenRecordID = meal.id.uuidString + "/" + (chicken?.id.uuidString ?? "")
                let mealIDs = try rows(database, "SELECT id FROM meal ORDER BY id").compactMap(\.first)
                let itemIDs = try rows(database, "SELECT id FROM item ORDER BY id").compactMap(\.first)
                let newerExchangeCount = try rows(database, "SELECT COUNT(*) FROM coach_index WHERE sequence > (SELECT sequence FROM coach_index WHERE turnID = '\(CoachCorrectionUITestFixture.id(1).uuidString)')").first?.first.flatMap(Int.init) ?? -1
                let latestPage = try await store.coachPage(.latest, expectedSelection: owner)
                let after = try await store.diaryHead(expectedProfileID: profileID)
                guard isCurrent() else { return }
                // The sole Store writer advances its head in the same actor operation as each commit.
                // No mixed revision or prior boundary may initialize a baseline or publish UI evidence.
                guard before == after, observedPhaseGeneration == phaseGeneration else { continue }
                if baselineBusiness == nil {
                    baselineBusiness = DiaryLaunch.defaults.string(forKey: "correction-ui-business")
                    baselineProtected = DiaryLaunch.defaults.string(forKey: "correction-ui-protected")
                    if baselineBusiness == nil {
                        guard accepted == nil, chicken?.quantity == (CoachCorrectionUITestFixture.scenario == "quantity" ? 200 : 2) else { throw DiaryError.invalidData }
                        baselineBusiness = business; baselineProtected = protectedDigest
                        DiaryLaunch.defaults.set(business, forKey: "correction-ui-business")
                        DiaryLaunch.defaults.set(protectedDigest, forKey: "correction-ui-protected")
                    }
                }
                let data: [String: Any] = ["phase": observedPhase, "revision": after.revision, "expired": expired, "auditReady": true,
                    "mealID": meal.id.uuidString, "dayID": meal.dayID.uuidString, "itemID": chicken?.id.uuidString ?? "",
                    "targetDate": day.day.localDate, "quantity": chicken?.quantity as Any? ?? NSNull(), "unit": chicken?.unit ?? "",
                    "mealIDs": mealIDs, "itemIDs": itemIDs, "unrelatedPreserved": protectedDigest == baselineProtected,
                    "businessUnchanged": business == baselineBusiness, "audit": audit,
                    "correctionApplications": audit.filter { $0[0] == chickenRecordID && Double($0[1]) == 2 && Double($0[2]) == 3 }.count,
                    "manualApplications": audit.filter { $0[0] == chickenRecordID && Double($0[2]) == 5 }.count,
                    "turnID": accepted?.id.uuidString ?? "", "sequence": accepted?.sequence as Any? ?? NSNull(),
                    "captureTrackingDayID": accepted?.trackingDayID?.uuidString ?? "", "captureSegmentID": accepted?.segmentID.uuidString ?? "",
                    "capturedAt": accepted?.capturedAt.timeIntervalSince1970 as Any? ?? NSNull(), "captureZone": accepted?.captureTimeZoneID ?? "",
                    "turnState": accepted?.state.rawValue ?? "", "assistantText": accepted?.assistantText ?? "",
                    "receiptCount": accepted?.receipts.count ?? 0, "receipt": try json(receipt),
                    "currentProfileZone": day.head.profile.timeZoneID, "processAt": CoachCorrectionUITestFixture.processInstant.timeIntervalSince1970,
                    "calls": calls, "contextMealIDs": contextMealIDs, "observedCommitOutput": observedCommitOutput,
                    "candidateMealIDs": candidateMealIDs, "groundedMealID": groundedMealID, "groundedItemIDs": groundedItemIDs,
                    "groundedQuantity": groundedQuantity as Any? ?? NSNull(),
                    "sourceOutsideLatest": !latestPage.exchanges.contains { $0.id == CoachCorrectionUITestFixture.id(1) },
                    "sourceTurnID": meal.sourceTurnID?.uuidString ?? "", "loadedCount": coach.turns.count, "newerExchangeCount": newerExchangeCount]
                facts = String(decoding: try JSONSerialization.data(withJSONObject: data, options: .sortedKeys), as: UTF8.self)
                return
            }
            throw DiaryError.staleRevision
        } catch {
            guard isCurrent(), observedPhaseGeneration == phaseGeneration else { return }
            facts = String(decoding: (try? JSONSerialization.data(withJSONObject: ["error": String(describing: error)])) ?? Data(), as: UTF8.self)
        }
    }
    func travel(_ coach: CoachViewModel) async {
        guard let owner = coach.diary.selection else { return }
        do {
            var profile = try await coach.diary.store.diaryHead(expectedProfileID: owner.identity.profileID).profile
            profile.timeZoneID = "Asia/Tokyo"
            try await coach.diary.store.updateProfile(profile, expectedProfileID: owner.identity.profileID)
            await refresh(coach)
        } catch { phase = "travel-failed" }
    }
    private struct PhotoFact: Encodable { let id: UUID; let role: PhotoRole; let createdAt: Date }
    private func json<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: .fragmentsAllowed) }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func digestRows(_ database: DiaryDatabase, tables: [String]) throws -> String {
        let values = try tables.map { table in try rows(database, "SELECT * FROM \(table) ORDER BY rowid") }
        return digest(try JSONSerialization.data(withJSONObject: values))
    }
    private func rows(_ database: DiaryDatabase, _ sql: String) throws -> [[String]] {
        let statement = try database.prepare(sql); defer { sqlite3_finalize(statement) }
        var values: [[String]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return values }
            guard status == SQLITE_ROW else { throw DiaryError.persistenceFailed }
            values.append((0..<sqlite3_column_count(statement)).map { index in
                if sqlite3_column_type(statement, index) == SQLITE_BLOB, let bytes = sqlite3_column_blob(statement, index) {
                    return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index))).base64EncodedString()
                }
                return sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "NULL"
            })
        }
    }
}

@MainActor struct CoachCorrectionFixtureControls: View {
    let coach: CoachViewModel
    @State private var state = CoachCorrectionFixtureState.shared
    var body: some View {
        HStack {
            Text("Correction facts").font(.caption2).accessibilityIdentifier("correctionFacts").accessibilityValue(state.facts)
            Button("Refresh") { Task { await state.refresh(coach) } }.accessibilityIdentifier("correctionRefresh")
            Button("Release") { state.release() }.accessibilityIdentifier("correctionRelease")
            Button("Travel") { Task { await state.travel(coach) } }.accessibilityIdentifier("correctionTravel")
            NavigationLink("Lunch") { MealDetailView(model: coach.diary, mealID: CoachCorrectionUITestFixture.id(910)) }
                .accessibilityIdentifier("correctionLunch")
        }.font(.caption2).buttonStyle(.borderless).frame(minHeight: 44)
        .task(id: coach.diary.selection) {
            await state.refresh(coach)
            guard let owner = coach.diary.selection else { return }
            for await _ in await coach.diary.store.changes(expectedProfileID: owner.identity.profileID) {
                guard !Task.isCancelled else { return }; await state.refresh(coach)
            }
        }
        .task(id: state.phase) { await state.refresh(coach) }
    }
}
#endif
