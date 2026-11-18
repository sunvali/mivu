# Time Zone Travel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The iOS diary follows the iPhone's time zone for frequent flyers. The travel day stays one day, meals show the time where they were eaten, and there's a one-tap way to keep the old zone for a trip.

**Architecture:** A pure `TimeZoneSync` decision, with per-profile state in `UserDefaults`, keeps `DiaryProfile.timeZoneID` in step with the device. It writes through the existing `DiaryStore.updateProfile`. The store stops assuming one zone for the whole diary: it finds days by date only, judges the day assignment in the current zone, and relaxes the Coach zone-equality guards. Meals gain an optional `timeZoneID`, which drives the display and the ✈︎ travel-day marker.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`import Testing`, `@Test`, `#expect`), XCTest UI tests, SQLite JSON payloads. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-17-time-zone-travel-design.md`

## Global Constraints

- iOS only. Android is out of scope, and `docs/parity.md` gets a row for it.
- Platform APIs only, no new dependencies. Follow Ponytail: minimal and readable Swift.
- English-only UI copy. Keep Dynamic Type, VoiceOver, reduced motion, and 44-pt minimum targets.
- Tests use synthetic inputs only (profile name "Synthetic", synthetic foods).
- Existing archives, backups and fixtures decode unchanged. New stored fields are optional and encoded only when non-nil (synthesized `encodeIfPresent`).
- Never re-time or move existing days, meals, weights, workouts or goals.
- Durable capture: retries send the same payload and manifest. Never drop a capture.
- Cutoff default 4 AM (`DayCutoff.hour`). Toast flip window: 3600 s.
- Copy: toast "Now on \(city) time" with the button "Keep \(oldCity)". Header tag "\(city) time". Tag action "Use \(deviceCity) time". Settings: "Set automatically" and "Time zone". Footer "Earlier meals keep the time where you ate them." Travel marker VoiceOver label "Travel day". Meal-time VoiceOver: "\(time), \(city) time".
- Native builds and tests run only on a Mac with XcodeBuildMCP (`test_sim`, project `ios/Mivu.xcodeproj`, scheme `Mivu`, test plan `Mivu`, `-only-testing:` the named suite, a reserved simulator UUID, and a checkout-specific DerivedData). This Linux workstation cannot run them. Record each blocked run as blocked, never as passed.
- Commits: Conventional titles. Do not mention codex or ai in commits or PRs.

## Review Focus

1. **The zone changes between preparing a Coach capture and saving it.** The capture must save once. → Test `coachCaptureSavesAfterZoneChangeBetweenPrepareAndCommit` (Task 3).
2. **A weight or workout entered with an exact time on the travel day, late evening in New York, which is already the next date in Tel Aviv.** It must save to the open travel day, not be rejected as invalid. → Test `lateWeightOnTravelDayIsAccepted` (Task 2).
3. **Old diaries that already have two days with the same date in different zones** (the Coach UI fixture has one). Lookup must prefer the active day, otherwise the earliest by `startAt`, and never throw. → Test `duplicateLegacyDatesResolveToActiveThenEarliest` (Task 2).
4. **Switching profiles while one is pinned.** Another profile's state must not change. → Test `stateIsPerProfile` (Task 1).
5. **A zone change while the app is open and a Coach reply is streaming.** The sync must wait for the worker and skip while sending, so the reply never goes stale. → Test `syncSkipsWhileCoachIsSending` (Task 5).

---

### Task 1: TimeZoneSync decision and per-profile state

**Files:**
- Create: `ios/Mivu/Diary/TimeZoneSync.swift`
- Test: `ios/MivuTests/TimeZoneSyncTests.swift`

**Interfaces:**
- Produces:
  - `enum TimeZoneMode: Codable, Equatable, Sendable { case automatic; case pinned(zone: String, untilDeviceZone: String?) }`
  - `struct TimeZoneSwitch: Codable, Equatable, Sendable { var from: String; var to: String; var at: Date; var announced: Bool }`
  - `struct TimeZoneState: Codable, Equatable, Sendable { var mode: TimeZoneMode; var knownProfileZone: String; var lastSwitch: TimeZoneSwitch? = nil }`
  - `struct TimeZoneDecision: Equatable { var state: TimeZoneState; var newProfileZone: String?; var announce: Bool }`
  - `enum TimeZoneSync { static func decide(state: TimeZoneState?, profileZone: String, deviceZone: String, now: Date) -> TimeZoneDecision; static func clockDiffers(_ a: String, _ b: String, at: Date) -> Bool; static func city(_ zoneID: String) -> String }`
  - `struct TimeZoneStateStore { init(defaults: UserDefaults); func state(for profileID: UUID) -> TimeZoneState?; func save(_ state: TimeZoneState, for profileID: UUID); func forget(_ profileID: UUID) }`. Key: `"timeZoneState." + profileID.uuidString`, JSON-encoded.

`decide` rules, in order (the spec's §1 and §4; this is the algorithm the tests pin down):
1. `state == nil` (migration): `mode = profileZone == deviceZone ? .automatic : .pinned(zone: profileZone, untilDeviceZone: nil)`, `knownProfileZone = profileZone`, no change, no announce.
2. `profileZone != state.knownProfileZone` (changed elsewhere: Settings, Coach `update_preferences`, restore): mode as in rule 1, `knownProfileZone = profileZone`, no change, no announce.
3. `.pinned(z, until)` and `until == deviceZone`: `mode = .automatic`, then continue to rule 4.
4. `.automatic` and `profileZone != deviceZone`: `newProfileZone = deviceZone`, `knownProfileZone = deviceZone`, `lastSwitch = TimeZoneSwitch(from: profileZone, to: deviceZone, at: now, announced: false)`. `announce` is true only when `clockDiffers(profileZone, deviceZone, at: now)` and (`state.lastSwitch == nil` or `now - state.lastSwitch!.at >= 3600`). When not announcing, store `announced: true` so a later open never shows it.
5. Otherwise, no change.

`city`: the last path component of the identifier, with `_` replaced by a space ("America/New_York" → "New York", "Asia/Tel_Aviv" → "Tel Aviv"). For "Asia/Jerusalem" this gives "Jerusalem", which is fine.

- [ ] **Step 1: Write the failing tests** in `TimeZoneSyncTests` (`struct TimeZoneSyncTests`, use `Date(timeIntervalSince1970: 1_800_000_000)` as `now`):

```swift
@Test func migrationKeepsMatchingZoneAutomaticAndOtherZonePinned() {
    #expect(TimeZoneSync.decide(state: nil, profileZone: "Asia/Jerusalem", deviceZone: "Asia/Jerusalem", now: now).state.mode == .automatic)
    let pinned = TimeZoneSync.decide(state: nil, profileZone: "Asia/Jerusalem", deviceZone: "America/New_York", now: now)
    #expect(pinned.state.mode == .pinned(zone: "Asia/Jerusalem", untilDeviceZone: nil) && pinned.newProfileZone == nil)
}
@Test func automaticFollowsTheDeviceAndAnnouncesAClockChange() {
    let d = TimeZoneSync.decide(state: auto("Asia/Jerusalem"), profileZone: "Asia/Jerusalem", deviceZone: "America/New_York", now: now)
    #expect(d.newProfileZone == "America/New_York" && d.announce && d.state.lastSwitch?.from == "Asia/Jerusalem")
}
@Test func sameOffsetSwitchIsSilent() {
    let d = TimeZoneSync.decide(state: auto("Europe/Paris"), profileZone: "Europe/Paris", deviceZone: "Europe/Berlin", now: now)
    #expect(d.newProfileZone == "Europe/Berlin" && !d.announce)
}
@Test func flipBackWithinAnHourIsSilent() {
    let first = TimeZoneSync.decide(state: auto("Asia/Jerusalem"), profileZone: "Asia/Jerusalem", deviceZone: "Asia/Amman", now: now)
    let back = TimeZoneSync.decide(state: first.state, profileZone: "Asia/Amman", deviceZone: "Asia/Jerusalem", now: now + 1800)
    #expect(back.newProfileZone == "Asia/Jerusalem" && !back.announce)
}
@Test func tripPinHoldsAwayAndReleasesAtHome() {
    let pin = TimeZoneState(mode: .pinned(zone: "Asia/Jerusalem", untilDeviceZone: "Asia/Jerusalem"), knownProfileZone: "Asia/Jerusalem")
    #expect(TimeZoneSync.decide(state: pin, profileZone: "Asia/Jerusalem", deviceZone: "America/New_York", now: now).newProfileZone == nil)
    let home = TimeZoneSync.decide(state: pin, profileZone: "Asia/Jerusalem", deviceZone: "Asia/Jerusalem", now: now)
    #expect(home.state.mode == .automatic && home.newProfileZone == nil && !home.announce)
}
@Test func outsideChangeToAnotherZonePinsWithoutRelease() {
    let d = TimeZoneSync.decide(state: auto("Asia/Jerusalem"), profileZone: "Asia/Tokyo", deviceZone: "Asia/Jerusalem", now: now)
    #expect(d.state.mode == .pinned(zone: "Asia/Tokyo", untilDeviceZone: nil) && d.newProfileZone == nil)
}
@Test func stateIsPerProfile() {
    let store = TimeZoneStateStore(defaults: UserDefaults(suiteName: "TimeZoneSync-" + UUID().uuidString)!)
    let a = UUID(), b = UUID()
    store.save(TimeZoneState(mode: .pinned(zone: "Asia/Jerusalem", untilDeviceZone: nil), knownProfileZone: "Asia/Jerusalem"), for: a)
    store.save(auto("UTC"), for: b)
    #expect(store.state(for: a)?.mode == .pinned(zone: "Asia/Jerusalem", untilDeviceZone: nil) && store.state(for: b)?.mode == .automatic)
}
@Test func cityNames() { #expect(TimeZoneSync.city("America/New_York") == "New York" && TimeZoneSync.city("UTC") == "UTC") }
```

`auto(_:)` is a private helper: `TimeZoneState(mode: .automatic, knownProfileZone: $0)`.

- [ ] **Step 2: Run the tests to make sure they fail.** XcodeBuildMCP `test_sim` with `-only-testing:MivuTests/TimeZoneSyncTests`. Expected: a build failure, because `TimeZoneSync` is undefined. On Linux, record it as blocked.
- [ ] **Step 3: Implement `TimeZoneSync.swift`** with the interfaces and rules above. `clockDiffers` compares `TimeZone(identifier:)!.secondsFromGMT(for: at)`.
- [ ] **Step 4: Run the tests again.** Expected: 8 tests pass. Zero tests run is a failure.
- [ ] **Step 5: Commit:** `feat(diary): decide when the diary follows the phone's time zone`

---

### Task 2: One day per date, and the travel-day assignment

**Files:**
- Modify: `ios/Mivu/Diary/DiaryDatabaseMealMutations.swift` (`resolveDay` ~261, `startDay`/`newDayLabel` ~288-298)
- Modify: `ios/Mivu/Diary/DiaryDatabaseManualNutrition.swift:107-113` (`dayAssignment`), plus the `.newCurrent` zone check below it
- Modify: `ios/Mivu/Diary/DiaryStore.swift:439` and `:579` (validate measured/performed times with the travel rule)
- Modify: `ios/Mivu/Diary/DiaryDatabaseProgress.swift:25,86` (workout `performedAt` date checks)
- Test: `ios/MivuTests/TimeZoneTravelTests.swift`, and replace `DayTests.timezoneChangeStartsADayInTheNewZoneAndPreservesHistory`

**Interfaces:**
- Produces:
  - `resolveDay(localDate:timeZoneID:at:newDayID:)` matches on `localDate` only. With several matches, it prefers `head.activeDayID`, otherwise the earliest `startAt`. It creates the day with the passed `timeZoneID` only when none exists.
  - `func instant(_ at: Date, fallsOn day: TrackingDay, profileZone: String) -> Bool` (a free function in `DiaryDatabaseMealMutations.swift`). True when `diaryDateLabel(at, zone: day.timeZoneID) == day.localDate`, or when `wakingDateLabel(at, zone: profileZone) <= day.localDate` and `at >= day.startAt` (the travel day). It replaces the plain date-equality checks for weights and workouts.
  - `dayAssignment(at:)` returns `.existing(id)` when `day.localDate >= wakingDateLabel(at, zone: head.profile.timeZoneID)`, whatever the day's zone.
  - `newDayLabel(at:)`: if the computed label is `<= active.localDate`, return the day after `active.localDate`, using `DiaryWeek` UTC label math.

- [ ] **Step 1: Write the failing tests** in `@Suite struct TimeZoneTravelTests`. Use `DayTests.ready(zone:at:)` and `DayTests.date(_:)`, and a helper `move(_ store, _ profile, to zone)` that calls `store.updateProfile` with the new `timeZoneID`:

```swift
@Test func telAvivToNewYorkKeepsTheDayUntilFourAMNewYork() async throws {
    let (store, profile, day) = try await DayTests.ready(zone: "Asia/Jerusalem", at: "2026-11-17T08:00:00Z")
    try await move(store, profile, to: "America/New_York")
    #expect(try await store.dayAssignment(at: DayTests.date("2026-11-17T20:00:00Z")) == .existing(day.id))
    #expect(try await store.dayAssignment(at: DayTests.date("2026-11-18T08:59:59Z")) == .existing(day.id))
    #expect(try await store.dayAssignment(at: DayTests.date("2026-11-18T09:00:00Z")) == .newDay)
    let next = try await store.startDay(at: DayTests.date("2026-11-18T09:00:00Z"))
    #expect(next.localDate == "2026-11-18" && next.timeZoneID == "America/New_York")
}
@Test func telAvivToTokyoStartsTheTokyoDate() async throws {
    let (store, profile, _) = try await DayTests.ready(zone: "Asia/Jerusalem", at: "2026-11-17T16:00:00Z")
    try await move(store, profile, to: "Asia/Tokyo")
    #expect(try await store.dayAssignment(at: DayTests.date("2026-11-18T04:00:00Z")) == .newDay)
    #expect(try await store.startDay(at: DayTests.date("2026-11-18T04:00:00Z")).localDate == "2026-11-18")
}
@Test func tokyoToHonoluluNeverGoesBackADate() async throws {
    let (store, profile, day) = try await DayTests.ready(zone: "Asia/Tokyo", at: "2026-11-18T00:00:00Z")
    try await move(store, profile, to: "Pacific/Honolulu")
    #expect(try await store.dayAssignment(at: DayTests.date("2026-11-18T06:00:00Z")) == .existing(day.id))
    #expect(try await store.dayAssignment(at: DayTests.date("2026-11-19T13:59:59Z")) == .existing(day.id))
    #expect(try await store.dayAssignment(at: DayTests.date("2026-11-19T14:00:00Z")) == .newDay)
    #expect(try await store.startDay(at: DayTests.date("2026-11-18T06:00:00Z")).localDate == "2026-11-19")
}
@Test func travelDateWritesReuseTheExistingDay() async throws {
    let (store, profile, day) = try await DayTests.ready(zone: "Asia/Jerusalem", at: "2026-11-17T08:00:00Z")
    try await move(store, profile, to: "America/New_York")
    let weight = try await store.recordWeight(value: 70, at: DayTests.date("2026-11-17T20:00:00Z"), startNewDay: false)
    _ = try await store.createWorkout(localDate: "2026-11-17", draft: syntheticWorkoutDraft, performedAt: nil, expectedProfileID: profile.id)
    let snapshot = try await store.snapshotForExport()
    #expect(snapshot.days.map(\.id) == [day.id] && weight.dayID == day.id)
}
@Test func lateWeightOnTravelDayIsAccepted() async throws {
    // 21:30 New York is already Nov 18 in Tel Aviv.
    let (store, profile, day) = try await DayTests.ready(zone: "Asia/Jerusalem", at: "2026-11-17T08:00:00Z")
    try await move(store, profile, to: "America/New_York")
    let saved = try await store.setWeight(dayLocalDate: "2026-11-17", value: 70, unit: "kg", measuredAt: DayTests.date("2026-11-18T02:30:00Z"), expectedRevision: nil, expectedProfileID: profile.id)
    #expect(saved.dayID == day.id)
}
@Test func duplicateLegacyDatesResolveToActiveThenEarliest() async throws { /* import a synthetic snapshot with two "2026-11-17" days (UTC and Pacific/Honolulu, the Honolulu one active); createWorkout(localDate: "2026-11-17") lands on the Honolulu day; after starting Nov 18, the earliest-startAt day wins */ }
```

`syntheticWorkoutDraft` comes from the existing workout tests in `ProgressStoreTests`. Delete `DayTests.timezoneChangeStartsADayInTheNewZoneAndPreservesHistory`, since the new tests supersede it. Keep its history-preserved assertion in `telAvivToNewYork…` as `#expect(try await store.snapshotForExport().days[0] == day)`.

- [ ] **Step 2: Run the tests to make sure they fail.** `-only-testing:MivuTests/TimeZoneTravelTests`. Expected: the `.newDay`, duplicate-day and invalid-data assertions fail.
- [ ] **Step 3: Implement** the five Interfaces items. In `resolveManualNutritionDay`'s `.newCurrent` case, drop `zone == head.profile.timeZoneID` and keep the date check.
- [ ] **Step 4: Run the tests again.** Run `TimeZoneTravelTests`, `DayTests`, `ProgressStoreTests`, `ManualNutritionTransactionTests`. Expected: all pass.
- [ ] **Step 5: Commit:** `feat(diary): keep one diary day per date across time zones`

---

### Task 3: Coach across a zone change

**Files:**
- Modify: `ios/Mivu/Diary/DiaryDatabaseMutations.swift:101` (drop the `context.timeZoneID == expected.profile.timeZoneID` clause)
- Modify: `ios/Mivu/Diary/DiaryDatabaseCoachMutations.swift:212` (`.startDay` guard) and `:223-236` (`coachDay`)
- Test: `ios/MivuTests/TimeZoneTravelTests.swift`

**Interfaces:**
- Consumes: Task 2's date-only `resolveDay` and `dayAssignment`.
- Produces:
  - `coachDay`: when `current` and `turn.activeDayID` points to the open day, and the requested date is that day's `localDate`, or the turn's waking date is `<=` it, return the open day. Otherwise keep the existing rollover/ambiguity logic.
  - `.startDay` guard: drop `turn.captureTimeZoneID == head.profile.timeZoneID`. Compare dates with `wakingDateLabel(turn.capturedAt, zone: turn.captureTimeZoneID)` against `wakingDateLabel(at, zone: head.profile.timeZoneID)`. Keep the `startAt <= capturedAt` clause.

- [ ] **Step 1: Write the failing tests.** Use `capturedTurn(...)` from `DiaryInterchangeTestSupport.swift`, and `store.applyCoachFood(turnID:targetLocalDate:items:expectedProfileID:)` with the synthetic apple `FoodItem` used in `CoachStoreTests`:

```swift
@Test func coachTurnFromTelAvivAppliesAfterLandingInNewYork() async throws {
    let (store, profile, day) = try await DayTests.ready(zone: "Asia/Jerusalem", at: "2026-11-17T08:00:00Z")
    let turn = try await capturedTurn(store, text: "Synthetic apple", photos: [], at: DayTests.date("2026-11-17T09:00:00Z"), expectedProfileID: profile.id)
    try await move(store, profile, to: "America/New_York")
    let receipt = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2026-11-17", items: [syntheticApple], expectedProfileID: profile.id)
    #expect(receipt.dayID == day.id && (try await store.snapshotForExport()).days.count == 1)
}
@Test func coachTodayIsTheOpenDayInHonolulu() async throws {
    let (store, profile, day) = try await DayTests.ready(zone: "Asia/Tokyo", at: "2026-11-18T00:00:00Z")
    try await move(store, profile, to: "Pacific/Honolulu")
    let turn = try await capturedTurn(store, text: "Synthetic apple", photos: [], at: DayTests.date("2026-11-18T06:00:00Z"), expectedProfileID: profile.id)
    let receipt = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2026-11-18", items: [syntheticApple], expectedProfileID: profile.id)
    #expect(receipt.dayID == day.id)
}
@Test func coachCaptureSavesAfterZoneChangeBetweenPrepareAndCommit() async throws {
    // Prepare with coachCapturePreparation under Tel Aviv, change the profile to New York, then captureCoachSubmission
    // with the same payload: it saves once, and a second identical call reconciles to the same exchange.
}
```

(Use the receipt's day field as named on `CoachReceipt`. If the field is not `dayID`, assert on the meal's `dayID` from the snapshot.)

- [ ] **Step 2: Run the tests to make sure they fail.** Expected: `ambiguousDay` and `staleRevision`.
- [ ] **Step 3: Implement** the Interfaces items.
- [ ] **Step 4: Run the tests again.** Run `TimeZoneTravelTests`, `CoachStoreTests`, `CoachCaptureTransactionTests`, `CoachClarificationTests`. Expected: all pass.
- [ ] **Step 5: Commit:** `fix(coach): apply captures and replies across a time zone change`

---

### Task 4: Meal zone, stored and shown

**Files:**
- Modify: `ios/Mivu/Diary/DiaryModels.swift:117` (`DiaryMeal`: add `var timeZoneID: String? = nil`)
- Modify: `ios/Mivu/Diary/DiaryReadModels.swift:44` (`MealReadModel`: add `var timeZoneID: String?`), and its projection at `DiaryDatabaseMealMutations.swift:220`
- Modify: the creation sites: `DiaryDatabaseMealMutations.swift:79` (`head.profile.timeZoneID`), `DiaryDatabaseManualNutrition.swift:19` (`head.profile.timeZoneID`), `DiaryDatabaseCoachMutations.swift:261` (`turn.captureTimeZoneID`). The Coach `log_food` path for a new meal sets it from the turn's capture zone too.
- Modify: `moveMeal` validation at `DiaryDatabaseMealMutations.swift:464` to use `instant(_:fallsOn:profileZone:)` from Task 2, with the meal zone as the first choice
- Create: `ios/Mivu/Diary/MealClock.swift`
- Modify display: `DiaryStyle.swift:273`, `MealDetailView.swift:316`, `HistoryView.swift` meal rows (not the sheet's `.environment(\.timeZone…)`), `CoachQuestionChips.swift:21`, `DiaryReport.swift:35`
- Test: `ios/MivuTests/MealClockTests.swift`, plus one decode test in `TimeZoneTravelTests`

**Interfaces:**
- Produces:
  - `enum MealClock { static func zone(meal: String?, day: String) -> String; static func label(_ at: Date, mealZone: String, deviceZone: String) -> (time: String, tag: String?, spoken: String) }`. `time` is `.shortened` in `mealZone`. `tag` is `TimeZoneSync.city(mealZone)` only when `TimeZoneSync.clockDiffers(mealZone, deviceZone, at:)`. `spoken` is `"\(time), \(city) time"` when tagged, otherwise `time`.
  - Display sites need the day's zone. Today has `model.activeDay`, and History and detail have the day. Pass `deviceZone: TimeZone.current.identifier`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func tagOnlyWhenTheClockDiffers() {
    let at = ISO8601DateFormatter().date(from: "2026-11-17T05:40:00Z")!
    let away = MealClock.label(at, mealZone: "Asia/Jerusalem", deviceZone: "America/New_York")
    #expect(away.tag == "Jerusalem" && away.spoken.hasSuffix(", Jerusalem time"))
    #expect(MealClock.label(at, mealZone: "Europe/Paris", deviceZone: "Europe/Berlin").tag == nil)
}
@Test func olderMealsFallBackToTheDayZone() { #expect(MealClock.zone(meal: nil, day: "Asia/Tokyo") == "Asia/Tokyo") }
```

In `TimeZoneTravelTests`:
- `newMealRecordsItsZoneAndOldPayloadsDecode`: capture a meal after `move(... "America/New_York")` and expect `timeZoneID == "America/New_York"`. JSON-decode a `DiaryMeal` payload without the key and expect `nil`. Encoding a meal with `nil` must not contain `"timeZoneID"`.
- `movingANewYorkDinnerWithinTheTravelDayIsValid`.

- [ ] **Step 2: Run the tests to make sure they fail.** `MealClockTests`, `TimeZoneTravelTests`.
- [ ] **Step 3: Implement** the model fields, creation sites, validation, `MealClock`, and the five display sites. Each tagged time renders as the time, then `" · \(tag)"` in `.diarySecondary`. Use `.accessibilityLabel(spoken)`.
- [ ] **Step 4: Run the tests again.** Run `MealClockTests`, `TimeZoneTravelTests`, `ArchiveFixtureTests`, `ArchiveTests`, `DiaryReportTests`. Expected: all pass, with fixtures unchanged.
- [ ] **Step 5: Commit:** `feat(diary): show each meal's time where it was eaten`

---

### Task 5: Sync the profile zone at every activity point

**Files:**
- Modify: `ios/Mivu/Diary/DiaryViewModel.swift` (add sync, keep and use, and published state; forget state on profile delete ~481)
- Modify: `ios/Mivu/MivuServices.swift` (`syncTimeZone()` wrapper)
- Modify: `ios/Mivu/Diary/TodayView.swift:183,237` (launch and foreground, before `rollOverDay`), plus a `.task` loop on `NotificationCenter.default.notifications(named: .NSSystemTimeZoneDidChange)`
- Modify: `ios/Mivu/Coach/TellCoachIntent.swift` (`TellCoach.run`: call `await services.syncTimeZone()` after `loadDiary`, before capture)
- Test: `ios/MivuTests/TimeZoneSyncViewModelTests.swift`

**Interfaces:**
- Consumes: Task 1's `TimeZoneSync`, `TimeZoneStateStore`, and `DiaryStore.updateProfile(_:expectedProfile:expectedProfileID:)`.
- Produces on `DiaryViewModel`:
  - `private(set) var timeZoneNotice: TimeZoneSwitch?` (set when `announce`, and cleared after `markTimeZoneNoticeShown()`)
  - `var timeZoneMode: TimeZoneMode?` (the selected profile's mode, read by Today and Settings)
  - `func syncTimeZone(now: Date = Date()) async`
  - `func keepPreviousTimeZone() async`: writes `lastSwitch.from` back to the profile and saves `.pinned(zone: from, untilDeviceZone: from)`
  - `func useDeviceTimeZone() async`: mode `.automatic`, then `syncTimeZone()`
  - `func setTimeZoneMode(automatic: Bool, zone: String?) async` (for Settings, Task 7)
  - `func markTimeZoneNoticeShown()`. A stored `lastSwitch` with `announced == false` from the same waking day is surfaced on the next `syncTimeZone`, then marked announced.
- Produces on `MivuServices`: `func syncTimeZone() async { await coach.waitForWorker(); guard !coach.isSending else { return }; await diary.syncTimeZone() }`
- `DiaryViewModel` reads state through `TimeZoneStateStore(defaults: preferences)`. With `preferences == nil` (tests that don't inject it), the sync is a no-op. The device zone comes from the injected `deviceTimeZone`.

- [ ] **Step 1: Write the failing tests** (`@Suite @MainActor`, following `ProfileTimezoneTests` with an injected `deviceTimeZone` and a fresh `UserDefaults(suiteName:)`):
  - `automaticSyncMovesTheProfileAndRaisesTheNotice`. The profile is created in "Asia/Jerusalem", the device reports "Asia/Jerusalem", and the first sync migrates. The device then reports "America/New_York". After the sync, `readModel?.profile.timeZoneID == "America/New_York"` and `timeZoneNotice?.from == "Asia/Jerusalem"`.
  - `keepPreviousRestoresAndPinsUntilHome`: after `keepPreviousTimeZone()`, the profile is "Asia/Jerusalem" and the mode is `.pinned(zone: "Asia/Jerusalem", untilDeviceZone: "Asia/Jerusalem")`. A sync with the device still in New York changes nothing.
  - `syncSkipsWhileCoachIsSending`: via `MivuServices` test wiring, or by asserting that the wrapper's guard is reached. If `MivuServices` can't be built in unit tests, test a small `static func shouldSync(isSending: Bool) -> Bool` and keep the wrapper a one-liner.
  - `existingPinnedProfileStaysPinnedOnFirstLaunch`: profile "Asia/Tokyo", device "Asia/Jerusalem". Nothing changes, and the mode is pinned.
- [ ] **Step 2: Run the tests to make sure they fail.** `-only-testing:MivuTests/TimeZoneSyncViewModelTests`.
- [ ] **Step 3: Implement** the Interfaces items and the four call sites. After a sync, the existing `readModel` change already republishes the widget snapshot and Live Activity (`TodayView.swift:189`), so add nothing there.
- [ ] **Step 4: Run the tests again.** Run `TimeZoneSyncViewModelTests`, `ProfileTimezoneTests`, `DiaryPreferencesDraftTests`, `TellCoachTests`, `WidgetSnapshotTests`. Expected: all pass.
- [ ] **Step 5: Commit:** `feat(diary): follow the phone's time zone when traveling`

---

### Task 6: Toast and pinned header tag

**Files:**
- Modify: `ios/Mivu/Diary/TodayView.swift`. Add a root overlay toast modeled on `quickLogToast` (~442), visible on any tab. Add the header tag next to Today's date.
- Modify: `ios/Mivu/Diary/DiaryViewModel.swift` (`DiaryLaunch`: add `static var isTimeZoneUITest: Bool`, from `--time-zone-ui-test`; in that mode, inject `deviceTimeZone = America/New_York` and a profile in "Asia/Jerusalem" with automatic state)
- Test: `ios/MivuUITests/TimeZoneTravelUITests.swift`

**Interfaces:**
- Consumes: Task 5's `timeZoneNotice`, `timeZoneMode`, `keepPreviousTimeZone()`, `useDeviceTimeZone()` and `markTimeZoneNoticeShown()`.
- Toast: text "Now on \(city(to)) time" and button "Keep \(city(from))" (a 44-pt target). Identifiers `timeZoneToast` and `timeZoneKeep`. It auto-dismisses after 6 s, which is the builder's choice per the spec. It's announced with `AccessibilityNotification.Announcement`. Under reduced motion it uses an opacity transition. It never blocks input.
- Header tag: shown when `timeZoneMode` is `.pinned` and `clockDiffers(profileZone, deviceZone)`. Text "\(city(profileZone)) time ›", identifier `pinnedZoneTag`. Tapping it shows a confirmation dialog with "Use \(city(device)) time" → `useDeviceTimeZone()`.

- [ ] **Step 1: Write the failing UI test:** `testZoneChangeShowsToastAndKeepPinsWithHeaderTag`. Launch with `["--time-zone-ui-test"]`. Expect `timeZoneToast` to exist and contain "New York". Tap `timeZoneKeep`. Expect `pinnedZoneTag` with the label "Jerusalem time ›". Tap it, confirm "Use New York time", and expect the tag to disappear.
- [ ] **Step 2: Run the test to make sure it fails.** `-only-testing:MivuUITests/TimeZoneTravelUITests` on the reserved simulator.
- [ ] **Step 3: Implement** the toast, the tag and the launch fixture.
- [ ] **Step 4: Run the test again,** plus `python3 scripts/ci/smoke.py --simulator-id <reserved-UUID>` (120 s cap). Expected: the UI test passes and smoke passes.
- [ ] **Step 5: Commit:** `feat(today): announce time zone changes and show a pinned zone`

---

### Task 7: Settings time zone section

**Files:**
- Modify: `ios/Mivu/Diary/SettingsView.swift:172,188,195`. Replace the `TextField("Timezone")` and the footer.
- Create: `ios/Mivu/Diary/TimeZonePicker.swift` (a searchable list)
- Modify: `ios/Mivu/Diary/DiaryViewModel.swift` (`DiaryPreferencesDraft`: the timezone field stays for conflict handling. The picker writes to it, and "Save preferences" no longer gates on a typed ID.)
- Test: `ios/MivuTests/TimeZonePickerTests.swift`

**Interfaces:**
- Consumes: Task 5's `setTimeZoneMode(automatic:zone:)` and `timeZoneMode`.
- Produces: `enum TimeZoneCatalog { static func entries(matching query: String, at: Date) -> [(id: String, city: String, offset: String)] }`. It draws from `TimeZone.knownTimeZoneIdentifiers`, matches city or identifier case-insensitively, sorts by city, and formats the offset as "GMT+2" or "GMT−5" (`secondsFromGMT(for: at)`).
- UI: `Toggle("Set automatically")` (identifier `timeZoneAutomatic`), then `NavigationLink` "Time zone" showing the city (identifier `timeZoneRow`), disabled while automatic. Choosing a city calls `setTimeZoneMode(automatic: false, zone: id)`. Turning the toggle on calls `setTimeZoneMode(automatic: true, zone: nil)`. Footer: "Earlier meals keep the time where you ate them."

- [ ] **Step 1: Write the failing tests:** `searchFindsNewYorkByCity` (`entries(matching: "new york", at: now).first?.id == "America/New_York"`) and `offsetFormatting` ("Asia/Tokyo" → "GMT+9").
- [ ] **Step 2: Run the tests to make sure they fail.** `-only-testing:MivuTests/TimeZonePickerTests`.
- [ ] **Step 3: Implement** the catalog, the picker and the Settings section.
- [ ] **Step 4: Run the tests again.** Run `TimeZonePickerTests` and `DiaryPreferencesDraftTests`, plus smoke (Settings is a screen change). Expected: all pass.
- [ ] **Step 5: Commit:** `feat(settings): set the time zone automatically or pick a city`

---

### Task 8: Travel-day marker

**Files:**
- Modify: `ios/Mivu/Diary/DiaryReadModels.swift:130` (`DiaryDaySummary`: add `var isTravelDay = false`), and `daySummary(_:)` at `DiaryDatabaseMealMutations.swift:238`
- Modify: `ios/Mivu/Progress/ProgressAnalytics.swift:6,78` (`DailyProgress`: add `var isTravelDay: Bool? = nil` so Codable caches still decode; `daily(...)` gets an `isTravelDay: Bool` parameter, with the caller passing whether any of that date's days is a travel day)
- Modify: the History day header (week strip or selected-day title in `HistoryView.swift`) and `ProgressDayRow` (`ProgressDetailViews.swift:116`): an `Image(systemName: "airplane")` with `.accessibilityLabel("Travel day")`
- Test: `ios/MivuTests/TimeZoneTravelTests.swift`

**Interfaces:**
- Produces: `func isTravelDay(dayZone: String, mealZones: [String?], at: Date) -> Bool`. True when the set of `secondsFromGMT(for: at)` over `mealZones.map { $0 ?? dayZone }` has more than one value. `daySummary` reads the zones with `SELECT DISTINCT json_extract(CAST(payload AS TEXT), '$.timeZoneID') FROM meal WHERE parent = ? AND json_extract(CAST(payload AS TEXT), '$.revision') > 0`. `at` is `day.startAt`.

- [ ] **Step 1: Write the failing tests:** `travelDayNeedsTwoOffsets` (["Asia/Jerusalem", nil] with day "Asia/Jerusalem" is false; ["America/New_York", nil] is true; ["Europe/Paris", "Europe/Berlin"] is false), and `historySummaryFlagsTheTravelDay` (capture one meal in Tel Aviv, move to New York, capture another, and expect `isTravelDay` on the day's summary).
- [ ] **Step 2: Run the tests to make sure they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the tests again.** Run `TimeZoneTravelTests`, `ProgressAnalyticsTests`, `ProgressStoreTests`, `DiaryWeekStripTests`. Expected: all pass.
- [ ] **Step 5: Commit:** `feat(history): mark travel days`

---

### Task 9: Coach local time and trip context

**Files:**
- Modify: `ios/Mivu/Diary/DiaryDatabaseMealMutations.swift:731` (`WakingDayInstruction`)
- Modify: `ios/Mivu/Coach/CoachEngine.swift:40` (call the new overload)
- Modify: `ios/Mivu/Analysis/AppleLocalInference.swift:88` (prepend the same instruction text to its context)
- Test: `ios/MivuTests/DayTests.swift` (extend `earlyMorningCaptureLetsCoachJudgeTheNightBefore`'s neighbours)

**Interfaces:**
- Produces: `static func text(context: CoachContext, cutoffHour: Int = DayCutoff.hour) -> String`. Let `open = context.days.first { $0.id == context.activeDayID }`.
  - If `open` exists and `wakingDateLabel(capturedAt, zone: captureTimeZoneID) <= open.localDate`, "today" is `open.localDate`.
  - If `open.timeZoneID` and `captureTimeZoneID` have different clocks at `capturedAt`, append: `"Local time \(HH:mm) in \(city(capture)); arrived from \(city(open.timeZoneID)) today; the open diary day is \(open.localDate). Times the person mentions are local."`
  - Otherwise, behave exactly like the existing `text(capturedAt:zone:)`, which stays and is used by it.

- [ ] **Step 1: Write the failing tests:** `travelContextNamesLocalTimeAndOpenDay` (an open day in "Asia/Jerusalem" on "2026-11-17", captured at "2026-11-17T20:10:00Z" in "America/New_York", contains "Local time 15:10 in New York", "arrived from Jerusalem" and "2026-11-17"), `honoluluTodayIsTheOpenDay` (an open "2026-11-18" Tokyo day, captured in Honolulu at "2026-11-18T06:00:00Z", contains "The current waking day is 2026-11-18"), and `sameZoneContextIsUnchanged` (equals `text(capturedAt:zone:)`).
- [ ] **Step 2: Run the tests to make sure they fail.** `-only-testing:MivuTests/DayTests`.
- [ ] **Step 3: Implement,** and switch both inference paths to the overload.
- [ ] **Step 4: Run the tests again.** Run `DayTests`, `CoachEngineTests`, `AppleInferenceTests`, `CoachContextMessagesTests`. Expected: all pass.
- [ ] **Step 5: Commit:** `feat(coach): tell Coach the local time and trip on travel days`

---

### Task 10: Parity, verification record, PR

**Files:**
- Modify: `docs/parity.md`. Add the row `| time-zone-travel | Time zone travel | post-baseline | [spec](superpowers/specs/2026-11-17-time-zone-travel-design.md) | partial | pending | - | iOS implemented; native verification pending on a Mac. Android not started. |`
- Create: `docs/verification/2026-11-17-time-zone-travel.md`: the source SHA, environment, each suite from Tasks 1-9 with result counts, or `blocked: Linux workstation, no Xcode`. Also the UI and smoke results. Physical-device travel is `blocked`.
- Modify: `docs/superpowers/specs/2026-10-20-day-rollover-design.md` rule 5. Point it to the new spec: "superseded by 2026-11-17 time zone travel".

- [ ] **Step 1:** Run `python3 scripts/ci/parity.py` and `python3 -m pytest scripts/ci/test_parity.py -q`. Expected: pass.
- [ ] **Step 2:** Commit: `docs: record time zone travel parity and verification`
- [ ] **Step 3:** Run Ponytail Review on the branch and fix blocking findings.
- [ ] **Step 4:** Push `feat/time-zone-travel` and open a PR titled `feat: follow the phone's time zone when traveling`. The description gives the summary, the verification record, and the blocked native gates stated plainly. Verify the hosted checks; they are script and title checks only.
