import Foundation
import Testing
@testable import Mivu

@Suite struct OnboardingTargetsTests {
    private func answers(sex: ProfileAbout.Sex, heightCm: Double, weightKg: Double, targetKg: Double, birthYear: Int,
                         pace: ProfileAbout.Pace = .steady) -> OnboardingAnswers {
        OnboardingAnswers(about: ProfileAbout(heightCm: heightCm, birthYear: birthYear, sex: sex, pace: pace),
                          weightKg: weightKg, targetKg: targetKg)
    }

    @Test func estimateLosesAtTheChosenPace() {
        let targets = answers(sex: .female, heightCm: 165, weightKg: 70, targetKg: 62, birthYear: 1990).estimate(year: 2026)
        #expect(targets == NutritionValues(kcal: 1360, carbs: 127, protein: 112, fat: 45))
    }

    @Test func estimateKeepsWeightWithTheMidpointWhenSexIsSkipped() {
        let targets = answers(sex: .unspecified, heightCm: 180, weightKg: 80, targetKg: 80, birthYear: 1996).estimate(year: 2026)
        #expect(targets.kcal == 2330)
    }

    @Test func estimateNeverGoesBelowTheFloor() {
        let targets = answers(sex: .female, heightCm: 150, weightKg: 45, targetKg: 40, birthYear: 1950, pace: .faster).estimate(year: 2026)
        #expect(targets.kcal == 1200)
    }

    @Test func losingBelowAHealthyWeightIsNotATarget() {
        #expect(answers(sex: .female, heightCm: 165, weightKg: 70, targetKg: 62, birthYear: 1990).targetIsHealthy)
        #expect(!answers(sex: .female, heightCm: 165, weightKg: 55, targetKg: 48, birthYear: 1990).targetIsHealthy)
        #expect(answers(sex: .female, heightCm: 165, weightKg: 45, targetKg: 48, birthYear: 1990).targetIsHealthy)
        #expect(answers(sex: .female, heightCm: 165, weightKg: 48, targetKg: 48, birthYear: 1990).targetIsHealthy)
    }

    @Test func replyIsAcceptedOnlyWhenTheNumbersHoldTogether() {
        let good = #"```json {"kcal":1800,"protein":120,"carbs":200,"fat":60,"explanation":"A steady deficit."} ```"#
        #expect(OnboardingTargets.parse(good)?.targets == NutritionValues(kcal: 1800, carbs: 200, protein: 120, fat: 60))
        #expect(OnboardingTargets.parse(good)?.explanation == "A steady deficit.")
        #expect(OnboardingTargets.parse(#"{"kcal":900,"protein":60,"carbs":90,"fat":30,"explanation":"Low."}"#) == nil)
        #expect(OnboardingTargets.parse(#"{"kcal":1800,"protein":50,"carbs":50,"fat":20,"explanation":"Off."}"#) == nil)
        #expect(OnboardingTargets.parse("Sorry, I can't help with that.") == nil)
    }

    @Test func oldProfilesDecodeWithoutAboutAndInvalidAboutIsRejected() throws {
        let old = try JSONDecoder().decode(DiaryProfile.self, from: Data(#"{"id":"\#(UUID())","name":"Synthetic","language":"en","timeZoneID":"UTC","preferences":""}"#.utf8))
        #expect(old.about == nil)
        var profile = DiaryProfile(name: "Synthetic", timeZoneID: "UTC")
        profile.about = ProfileAbout(heightCm: 400, birthYear: 1990)
        #expect(throws: DiaryError.self) {
            try validateDiaryMetadataFields(schemaVersion: 1, revision: 0, profile: profile, lineage: nil, previousDayConfirmedAt: nil)
        }
    }
}

@Suite @MainActor struct OnboardingSetupSaveTests {
    @Test func setupFinishedBeforeTheCutoffSetsTodaysGoal() async throws {
        let store = DiaryStore(directory: URL.temporaryDirectory.appending(path: "OnboardingSave-" + UUID().uuidString))
        let profile = DiaryProfile(name: "Synthetic setup", timeZoneID: "Asia/Jerusalem")
        _ = try await store.createProfile(profile)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        let afterMidnight = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 0, minute: 30)))
        let answers = OnboardingAnswers(about: ProfileAbout(heightCm: 165, birthYear: 1990, sex: .female, pace: .steady), weightKg: 70, targetKg: 62)
        let targets = NutritionValues(kcal: 1800, carbs: 200, protein: 120, fat: 60)

        try await OnboardingView.saveSetup(answers, targets: targets, savedWeightKg: nil, profile: profile, store: store, at: afterMidnight)

        #expect(try await store.diaryReadModel(expectedProfileID: profile.id).activeGoal?.targets == targets)
    }
}
