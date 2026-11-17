import Foundation
import Testing
@testable import Mivu

@Suite struct HealthWorkoutTests {
    private func session(source: WorkoutBurnSource?, name: String?, burn: Double? = nil) -> WorkoutSession {
        WorkoutSession(dayID: UUID(), performedAt: Date(timeIntervalSince1970: 1_800_000_000), timePrecision: .exact, revision: 1,
                       kind: .cardio, durationMinutes: 45, exercises: [], estimatedBurnKcal: burn, burnSource: source, healthSource: name)
    }

    @Test func oldWorkoutPayloadDecodesWithoutHealthSource() throws {
        let saved = session(source: .userEstimate, name: nil, burn: 200)
        let json = try JSONEncoder().encode(saved)
        #expect(!String(decoding: json, as: UTF8.self).contains("healthSource"))
        let decoded = try JSONDecoder().decode(WorkoutSession.self, from: json)
        #expect(decoded.healthSource == nil)
        #expect(!decoded.isFromHealth)
    }

    @Test func healthWorkoutRequiresSourceName() throws {
        try validateWorkoutFields(session(source: .health, name: "Garmin Connect", burn: 412))
        try validateWorkoutFields(session(source: .health, name: "Garmin Connect"))
        #expect(throws: DiaryError.invalidData) { try validateWorkoutFields(session(source: .health, name: nil)) }
        #expect(throws: DiaryError.invalidData) { try validateWorkoutFields(session(source: .health, name: " ")) }
        #expect(throws: DiaryError.invalidData) { try validateWorkoutFields(session(source: .health, name: String(repeating: "a", count: 101))) }
        #expect(throws: DiaryError.invalidData) { try validateWorkoutFields(session(source: .userEstimate, name: "Garmin Connect", burn: 1)) }
    }

    @Test func detailIsReadOnlyForHealth() {
        let garmin = WorkoutDetailPresentation(session: session(source: .health, name: "Garmin Connect", burn: 412.4))
        #expect(!garmin.canEdit && garmin.sourceLine == "From Garmin Connect" && garmin.burnLine == "Active calories: 412 kcal")
        #expect(WorkoutDetailPresentation(session: session(source: .health, name: "Garmin Connect")).burnLine == "No calories from Health")
        let coach = WorkoutDetailPresentation(session: session(source: nil, name: nil))
        #expect(coach.canEdit && coach.sourceLine == nil && coach.burnLine == "Estimated burn: unknown")
    }

    @Test func coachCannotClaimHealthAsBurnSource() {
        func call(_ source: String) -> CoachToolCall {
            CoachToolCall(id: "synthetic", callID: "synthetic", name: "log_workout", namespace: "mivu",
                          arguments: #"{"local_date":"2027-01-15","kind":"cardio","duration_minutes":30,"exercises":[],"estimated_burn_kcal":300,"burn_source":"\#(source)"}"#)
        }
        #expect((try? CoachTools.parse(call("userEstimate"), meals: [], evidence: [:], receipts: [])) != nil)
        #expect(throws: CoachError.invalidArguments) { try CoachTools.parse(call("health"), meals: [], evidence: [:], receipts: []) }
    }
}
