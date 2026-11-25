import Foundation
import Testing
@testable import Mivu

/// A synthetic diary of 21 closed days ending yesterday, on target for calories and, by default, short on protein.
@Suite @MainActor struct PipNoticeLoadingTests {
    private let now = ISO8601DateFormatter().date(from: "2026-11-26T12:00:00Z")!
    private let today = "2026-11-26"
    private let short = PipNotice.proteinShort(short: 14, days: 14)

    private func snapshot(name: String = "Synthetic notices", protein: Double = 50, mealToday: Bool = false) -> DiarySnapshot {
        var days: [TrackingDay] = [], meals: [DiaryMeal] = []
        for offset in (0...21).reversed() {
            let start = now.addingTimeInterval(TimeInterval(-offset * 86_400 - 12 * 3600))
            let day = TrackingDay(localDate: diaryDateLabel(start, zone: "UTC"), timeZoneID: "UTC", startAt: start, completeness: offset == 0 ? .unknown : .complete)
            days.append(day)
            guard offset > 0 || mealToday else { continue }
            let eaten = start.addingTimeInterval(9 * 3600)
            meals.append(DiaryMeal(dayID: day.id, capturedAt: eaten, eatenAt: eaten, revision: 1,
                items: [FoodItem(name: "Synthetic bowl", quantity: 1, unit: "bowl", nutrition: NutritionValues(kcal: 2000, carbs: 200, protein: protein, fat: 60),
                                 provenance: .estimate, reference: "Synthetic bowl")],
                submissions: [MealSubmission(baseRevision: 0, text: "Synthetic bowl", photoIDs: [], reviewFirst: false, state: .saved)]))
        }
        let goal = GoalRecord(effectiveLocalDate: days[0].localDate, timeZoneID: "UTC",
                              targets: NutritionValues(kcal: 2000, carbs: 200, protein: 100, fat: 60), goalWeightKg: nil, exerciseCreditEnabled: false)
        return DiarySnapshot(revision: 1, profile: DiaryProfile(name: name, timeZoneID: "UTC"), days: days, meals: meals, goals: [goal],
                             activeDayID: days.last?.id, previousDayConfirmedAt: now)
    }

    private struct Fixture {
        let diary: DiaryViewModel, store: DiaryStore, defaults: UserDefaults, profileID: UUID, root: URL
        var log: PipNoticeLog { PipNoticeStore(defaults: defaults).log(for: profileID) }
    }
    private func fixture(_ snapshot: DiarySnapshot? = nil) async throws -> Fixture {
        let root = URL.temporaryDirectory.appending(path: "PipNotice-" + UUID().uuidString), clock = now
        let store = DiaryStore(directory: root, currentTime: { clock })
        let profileID = try await store.importProfile(snapshot ?? self.snapshot()).head.profile.id
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let diary = DiaryViewModel(store: store, preferences: defaults, deviceTimeZone: { TimeZone(identifier: "UTC")! })
        await diary.load(createDefaultProfile: false)
        if diary.readModel?.head.profile.id != profileID { await diary.switchProfile(profileID) }
        #expect(diary.activeDay?.localDate == today)
        return Fixture(diary: diary, store: store, defaults: defaults, profileID: profileID, root: root)
    }
    private let neverScan: @Sendable (DiaryStore, UUID, String, String) async -> [PipNotice]? = { _, _, _, _ in
        Issue.record("The diary was scanned when it should not have been."); return []
    }

    @Test func loadsOnceADay() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        await f.diary.loadPipNotice()
        #expect(f.diary.todaysPipNotice == short)
        #expect(f.diary.visiblePipNotice == short)
        #expect(f.log == PipNoticeLog(scanned: today, shown: [.init(localDate: today, notice: short)]))
        await f.diary.loadPipNotice(scan: neverScan)
        #expect(f.diary.todaysPipNotice == short)
        #expect(f.log.shown.count == 1)
    }

    @Test func quietDayIsNotScannedAgain() async throws {
        let f = try await fixture(snapshot(protein: 100)); defer { try? FileManager.default.removeItem(at: f.root) }
        await f.diary.loadPipNotice()
        #expect(f.diary.todaysPipNotice == nil)
        #expect(f.log == PipNoticeLog(scanned: today))
        await f.diary.loadPipNotice(scan: neverScan)
    }

    @Test func failedReadTriesAgainLater() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        await f.diary.loadPipNotice(scan: { _, _, _, _ in nil })
        #expect(f.diary.todaysPipNotice == nil)
        #expect(f.log == PipNoticeLog())
        await f.diary.loadPipNotice()
        #expect(f.diary.todaysPipNotice == short)
    }

    @Test func savedMealHidesButCoachStillKnows() async throws {
        let f = try await fixture(snapshot(mealToday: true)); defer { try? FileManager.default.removeItem(at: f.root) }
        await f.diary.loadPipNotice()
        #expect(f.diary.visiblePipNotice == nil)
        #expect(f.diary.todaysPipNotice == short)
    }

    @Test func offerTapHidesIt() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        await f.diary.loadPipNotice()
        f.diary.markPipOfferTapped()
        #expect(f.diary.visiblePipNotice == nil)
        #expect(f.diary.todaysPipNotice == short)
        #expect(f.log.shown.last?.offerTapped == true)
        await f.diary.loadPipNotice(scan: neverScan)
        #expect(f.diary.visiblePipNotice == nil)
    }

    @Test func switchOffClearsBoth() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        await f.diary.loadPipNotice()
        f.defaults.set(false, forKey: PipNoticeStore.enabledKey)
        #expect(f.diary.visiblePipNotice == nil)
        #expect(f.diary.todaysPipNotice == nil)
        f.defaults.set(true, forKey: PipNoticeStore.enabledKey)
        #expect(f.diary.visiblePipNotice == short)
    }

    @Test func switchedOffNeverScans() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        f.defaults.set(false, forKey: PipNoticeStore.enabledKey)
        await f.diary.loadPipNotice(scan: neverScan)
        #expect(f.diary.todaysPipNotice == nil)
        #expect(f.log == PipNoticeLog())
    }

    @Test func newDayDoesNotCarryYesterdaysNotice() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        await f.diary.loadPipNotice()
        await f.diary.rollOverDay(at: now.addingTimeInterval(86_400))
        #expect(f.diary.activeDay?.localDate == "2026-11-27")
        #expect(f.diary.todaysPipNotice == nil)
        // The same kind rests for a week, so the new day has nothing to add.
        await f.diary.loadPipNotice()
        #expect(f.diary.todaysPipNotice == nil)
        #expect(f.log.scanned == "2026-11-27")
        #expect(f.log.shown.count == 1)
    }

    @Test func profileSwitchDuringLoadAssignsNothing() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let other = try await f.store.importProfile(snapshot(name: "Synthetic other")).head.profile.id
        await f.diary.switchProfile(f.profileID)
        let (entered, hasEntered) = AsyncStream<Void>.makeStream(), (release, doRelease) = AsyncStream<Void>.makeStream()
        let diary = f.diary
        let load = Task { await diary.loadPipNotice(scan: { _, _, _, _ in
            hasEntered.yield()
            for await _ in release { break }
            return [.welcomeBack]
        }) }
        for await _ in entered { break }
        await f.diary.switchProfile(other)
        doRelease.yield(); await load.value
        #expect(f.diary.readModel?.head.profile.id == other)
        #expect(f.diary.todaysPipNotice == nil)
        #expect(f.log == PipNoticeLog())
        #expect(PipNoticeStore(defaults: f.defaults).log(for: other) == PipNoticeLog())
    }
}
