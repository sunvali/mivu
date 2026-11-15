# Coach on the Open Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sideways on iPhone Duo, the pane beside the Coach chat shows what the conversation is about (a meal, a workout, another day, Progress) instead of always Today, with the chat on the right.

**Architecture:** One optional value, `CoachPane?` (nil means Today), owned by `DiaryRootView`, decides what the side pane shows. The pane is a `NavigationStack` whose root is the live Today and whose single pushed destination is that value, so the system back button returns to Today. Sideways the value drives the pane; upright the same value drives the existing push over the chat. Pure functions decide automatic jumps and follow-up buttons, so they are unit tested without a simulator.

**Tech Stack:** Swift, SwiftUI, Swift Testing (`MivuTests`), XCTest UI tests (`MivuUITests`), XcodeBuildMCP, iPhone Duo simulator (iOS 27.1).

**Spec:** `docs/superpowers/specs/2026-11-14-coach-open-screen-design.md`

## Global Constraints

- Work in a new worktree from `origin/main` (baseline `97731611`), never in the `codex/mivu-icon-wordmark` tree. Copy the spec and this plan into the first PR.
- Four PRs, in order, each from `main` with a Conventional Commit title: `feat/duo-coach-pane` (Tasks 1–4), `feat/duo-pane-expand` (Task 5), `feat/duo-diary-columns` (Task 6), `fix/duo-half-width` (Task 7).
- No mention of any assistant or tool in commits, PRs, branch names or comments.
- Upright inner display, the outer display and non-Duo iPhones behave exactly as on `main`. Nothing splits the upright screen.
- Chat on the right, side pane on the left, sideways flat and in book pose. Table pose unchanged.
- Coach rules from AGENTS.md: bounded owner queries, no rebuilt `DiarySnapshot`, the 100-exchange window untouched, committed receipts immutable, "Jump to latest" stays the native glass button owned by `CoachTimelineTable`.
- Nothing new is stored. No new Coach tools or prompts. No dependency. Reuse `DuoSplit` / `DuoBeside`.
- Only one animated Pip rig: the pane never mounts a rig.
- Dynamic Type, VoiceOver, reduced motion, 44-point targets. At accessibility text sizes `isWideLayout` is false, so everything behaves as upright.
- Failing test first. Run only the named tests with XcodeBuildMCP on the iPhone Duo simulator; record the source SHA and counts in `docs/verification/2026-11-14-coach-open-screen.md`.
- Duo simulator rules: type with the on-screen keyboard; after any layout change walk all four tabs through upright, sideways, book and table and check CPU returns to idle; the inner display is `--display=3`.
- Pre-push hook needs Android Studio's `JAVA_HOME`.

## Review Focus

1. **Opening the app or paging old chat moves the pane.** Expected: only receipts first seen in this session cause a jump. Test: Task 1 `firstObservationNeverJumps`, `seenReceiptsNeverJump`.
2. **A change commits while a sheet is open in the pane.** Expected: the pane stays, the edit is not lost, and the skipped change does not jump later. Test: Task 1 `openSheetSkipsTheJump`; Task 3 step 6 pins "seen" being updated anyway.
3. **The meal shown in the pane is deleted** (by Coach, by undo, or by hand). Expected: the pane returns to Today, not an empty detail. Test: Task 3 `testDeletingPaneMealReturnsToToday`.
4. **Profile switch while the pane shows the old profile's record.** Expected: pane back to Today, not expanded. Task 3 step 6 resets it on `coach.diary.selection` change; verified by hand in Task 4, since the UI fixtures have one profile.
5. **Rotation with the keyboard up and a draft typed.** Expected: draft, chat position and pane content survive sideways → upright → sideways; the chat stays the mounted pane. Test: manual on the Duo simulator in Task 4 (XCUITest cannot rotate the inner display).

---

## File Structure

- Create `ios/Mivu/Coach/CoachPane.swift`: the `CoachPane` value and the pure decisions (landing, follow-ups).
- Create `ios/Mivu/Coach/CoachSidePane.swift`: the pane view (Today root, pushed destination, expand button).
- Modify `ios/Mivu/Coach/CoachEngine.swift`, `CoachViewModel.swift`: session-only "what Coach read" signal.
- Modify `ios/Mivu/Coach/CoachReplyLines.swift`, `CoachView.swift`: follow-ups and record taps route through the pane.
- Modify `ios/Mivu/Design/DuoLayout.swift`: `DuoSplit` / `DuoBeside` side order and fill.
- Modify `ios/Mivu/Diary/TodayView.swift` (`DiaryRootView.rootTabs`), `HistoryView.swift`, `ios/Mivu/Progress/ProgressView.swift`.
- Tests: create `ios/MivuTests/CoachPaneTests.swift`; modify `ios/MivuTests/CoachEngineTests.swift`, `ios/MivuUITests/DuoLayoutUITests.swift`.

---

### Task 1: `CoachPane` and its decisions

**Files:**
- Create: `ios/Mivu/Coach/CoachPane.swift`
- Modify: `ios/Mivu/Coach/CoachReplyLines.swift:35-40` (`FollowUp`, `followUps`)
- Test: `ios/MivuTests/CoachPaneTests.swift`

**Interfaces:**
- Produces:
  - `enum CoachPane: Hashable, Sendable { case day(String), meal(UUID), workout(UUID), progress }` (the `String` is a local date; `nil` of `CoachPane?` means Today).
  - `enum CoachConsulted: Hashable, Sendable { case progress, day(String) }`
  - `struct CoachPaneLanding: Equatable { var pane: CoachPane?; var jumps: Bool }`
  - `static func CoachPane.landing(seen: Set<String>?, receipts: [CoachCommittedReceipt], activeDayID: UUID?, modalOpen: Bool) -> CoachPaneLanding`
  - `CoachReplyLines.FollowUp` becomes `case today, progress, day(String)` with `var pane: CoachPane?`
  - `static func CoachReplyLines.followUps(for turn: CoachExchangeSummary, consulted: [CoachConsulted] = [], today: String? = nil) -> [FollowUp]`

Landing rules, in order: `seen == nil` → no jump; `modalOpen` → no jump; among receipts whose `operationKey` is not in `seen`, take the last that maps: `weightID != nil` and key does not contain `"/delete_weight/"` → `.progress`; `mealID` or `workoutID` set with `dayID == activeDayID` → Today (`pane: nil, jumps: true`); otherwise with `targetLocalDate` → `.day(date)`; anything else (goals, settings, no date) → no jump.

Follow-up rules: keep the two existing ones; add `.progress` when `consulted` contains `.progress`; add `.day(d)` for each consulted day where `d != today`, and `.today` where `d == today`; no duplicates; only for `.completed` turns.

- [ ] **Step 1: Write the failing tests** in `CoachPaneTests` (Swift Testing, same style as `DuoLayoutTests`). Build receipts with a small local helper that sets only `operationKey`, `turnID`, `dayID`, `mealID`, `workoutID`, `weightID`, `targetLocalDate`, `committedRevision`.

```swift
@Test func firstObservationNeverJumps()      // seen: nil, a today meal → jumps == false
@Test func seenReceiptsNeverJump()           // seen contains the key → jumps == false
@Test func openSheetSkipsTheJump()           // modalOpen: true → jumps == false
@Test func mealOnActiveDayLandsOnToday()     // → CoachPaneLanding(pane: nil, jumps: true)
@Test func mealOnAnotherDayLandsOnThatDay()  // targetLocalDate "2026-11-10" → pane == .day("2026-11-10")
@Test func workoutOnAnotherDayLandsOnThatDay()
@Test func weightLandsOnProgress()           // key "weight/2026-11-14" → .progress
@Test func deletedWeightDoesNotJump()        // key "x/delete_weight/y" → jumps == false
@Test func goalChangeDoesNotJump()           // only goalID set → jumps == false
@Test func lastNewReceiptWins()              // new meal (today) then new weight → .progress
@Test func consultedProgressOffersSeeProgress()   // followUps(consulted: [.progress]) == [.progress]
@Test func consultedOtherDayOffersThatDay()       // [.day("2026-11-10")], today "2026-11-14" → [.day("2026-11-10")]
@Test func consultedTodayOffersToday()            // [.day("2026-11-14")], today "2026-11-14" → [.today]
@Test func followUpsHaveNoDuplicates()            // weight receipt + consulted .progress → one .progress
```

- [ ] **Step 2: Run `MivuTests/CoachPaneTests`.** Expected: FAIL to compile (`CoachPane` not found).
- [ ] **Step 3: Implement** the types and two functions above. `FollowUp.pane`: `.today → nil`, `.progress → .progress`, `.day(d) → .day(d)`.
- [ ] **Step 4: Run `MivuTests/CoachPaneTests`.** Expected: 14 passed.
- [ ] **Step 5: Commit** `feat(duo): decide what the Coach side pane shows`.

### Task 2: Session-only "what Coach read" signal

**Files:**
- Modify: `ios/Mivu/Coach/CoachEngine.swift:9-11,163-170`, `ios/Mivu/Coach/CoachViewModel.swift:35-36,~502`
- Test: `ios/MivuTests/CoachEngineTests.swift`

**Interfaces:**
- Consumes: `CoachConsulted` (Task 1).
- Produces:
  - `CoachEngine.init(..., onConsulted: @escaping @Sendable (CoachConsulted) async -> Void = { _ in })`, called for `.progress` commands (`.progress`) and `.meals(date:afterMealID:)` commands (`.day(date)`), next to the existing `onActivity(.reading)`.
  - `CoachViewModel.consulted(_ turnID: UUID) -> [CoachConsulted]`: what the engine read for that turn in this session; empty for any other turn. Cleared when the diary selection changes.

- [ ] **Step 1: Write the failing test** `progressAndDayReadsAreReported` in `CoachEngineTests`, using the file's existing `fixture()` and scripted inference: script a `progress(endingOn:days:)` command and a `meals(date: "2026-11-10", afterMealID: nil)` command before the final reply; collect `onConsulted` calls; expect `[.progress, .day("2026-11-10")]`.
- [ ] **Step 2: Run that test.** Expected: FAIL to compile (extra argument `onConsulted`).
- [ ] **Step 3: Implement.** In the view model, keep `private var consultedByTurn: (turnID: UUID, items: [CoachConsulted])?`, appended from the closure beside `onActivity` using the turn the engine was started for. `// shortcut: session only, lost on relaunch; store with the turn if users miss the button.`
- [ ] **Step 4: Run `MivuTests/CoachEngineTests`.** Expected: all pass, including the new test.
- [ ] **Step 5: Commit** `feat(coach): note what a reply read, for this session`.

### Task 3: Chat on the right, pane follows taps and changes

**Files:**
- Create: `ios/Mivu/Coach/CoachSidePane.swift`
- Modify: `ios/Mivu/Design/DuoLayout.swift` (`DuoSplit`, `DuoBeside`), `ios/Mivu/Diary/TodayView.swift:386-406` (Coach tab), `ios/Mivu/Coach/CoachView.swift:36-42,103,118-126,190-192,666-670,740-742,754-766,775`, `ios/Mivu/Diary/HistoryView.swift:8,93`, `ios/Mivu/Progress/ProgressView.swift`
- Test: `ios/MivuUITests/DuoLayoutUITests.swift`

**Interfaces:**
- Consumes: `CoachPane`, `CoachPane.landing`, `FollowUp.pane` (Task 1); `coach.consulted(_:)` (Task 2).
- Produces:
  - `DuoSplit(axis:showsSecondary:followsCrease:secondaryLeading:)` and `DuoBeside(secondaryLeading:)`, default `false`. When true the secondary is laid out first (left), and `primary` still keeps its identity while the secondary comes and goes.
  - `CoachView(..., pane: Binding<CoachPane?>)` replacing the private `selectedRecord` state.
  - `struct CoachSidePane: View { init(model: DiaryViewModel, companionRuntime: CompanionRuntime, pane: Binding<CoachPane?>) }`, identifier `coachSidePane`; its Today root keeps identifier `coachLiveDay`.
  - `HistoryView(model:startDate: String? = nil)`: the day selected on first appearance.
  - `DiaryProgressView(model:openDiary:showsCompanion: Bool = true)`: `false` renders no `CompanionView` and never touches `companionRuntime`.

- [ ] **Step 1: Write the failing UI tests** in `DuoLayoutUITests` (launch with `--wide-layout-ui-test`, `--coach-ui-test`, `--coach-inference-fixture`, `--proof-english`; skip when the window is narrower than 760 like the existing tests).

```swift
func testSidewaysChatSitsRightOfThePane()
// coachSidePane.frame.maxX <= coachInput.frame.minX + 1

func testSidewaysTapOpensMealBesideChat()
// send "Two eggs, three bread slices and salad"; tap the receipt card;
// "mealDetail" exists inside coachSidePane's frame; coachInput still exists and isHittable;
// tap the pane's back button "Today" → coachLiveDay exists again.

func testSidewaysSeeProgressOpensInPane()
// log a weight through Coach; tap "coachFollowUp-progress";
// "progressPrimaryColumn" or the Progress title exists inside coachSidePane; tab bar still selects Coach.

func testDeletingPaneMealReturnsToToday()
// open the meal in the pane, delete it there (confirm) → coachLiveDay exists, no "mealDetail".

func testUprightTapStillPushesOverChat()
// launch without --wide-layout-ui-test, skip unless the window is upright;
// tap the receipt card → "mealDetail" exists and coachSidePane does not.
```

Also flip the existing `testSidewaysCoachShowsLiveDayAndHighlightsChange` assertion to `changed.frame.maxX < input.frame.minX + 1` ("The live day sits left of the chat"). If `MealDetailView` has no `mealDetail` identifier on `main`, add it to its root view.

- [ ] **Step 2: Run the five new tests plus the flipped one.** Expected: FAIL (`coachSidePane` not found; live day is right of the chat).
- [ ] **Step 3: `DuoSplit` / `DuoBeside` side order.** Add `secondaryLeading`. With a crease, the leading pane takes the width up to `crease.minX`, then the crease gap, then the trailing pane flexes; `primary`'s position in the builder must stay fixed so it never remounts.
- [ ] **Step 4: `CoachSidePane`.** `NavigationStack { TodayView(isLiveDay: true, still Pip as today) .navigationDestination(item: pane) { … } }` with: `.meal(id)` → `MealDetailView(model:mealID:)`, `.workout(id)` → `WorkoutDetailView(model:sessionID:)`, `.day(date)` → `HistoryView(model:startDate: date).id(date)`, `.progress` → `DiaryProgressView(model:openDiary: {}, showsCompanion: false)`. Keep the secondary's compact environment from `DuoBeside`. Move `.ignoresSafeArea(.container, edges: .trailing)` from `CoachView:103` to wherever the Duo simulator shows it is needed now that the chat is the page beside the system control strip; neither page may show a bare band or content under the strip.
- [ ] **Step 5: Route taps in `CoachView`.** Every `selectedRecord = .meal(id)` / `.workout(id)` becomes `pane = .meal(id)` / `.workout(id)`. The `navigationDestination` item becomes a binding that is non-nil only when `!isWide` and `pane` is `.meal`, `.workout` or `.day` (setting nil clears `pane`); its `.day(date)` case shows `HistoryView(model:startDate:)`. Follow-up buttons: when `isWide`, set `pane = followUp.pane`. Upright, `.today` and `.progress` keep calling `openToday` / `openProgress` exactly as on `main`, and the new `.day(d)` sets `pane = .day(d)`, which pushes that day over the chat. Build the list with `CoachReplyLines.followUps(for: turn, consulted: coach.consulted(turn.id), today: coach.diary.activeDay?.localDate)` and, when `isWide`, hide any follow-up whose `pane` equals the current `pane`. Button titles: "See today", "See progress", `"See " + CoachReplyLines.shortDate(d)`; identifier `coachFollowUp-day` for the new one.
- [ ] **Step 6: Automatic landing.** In `DiaryRootView` add `@State private var coachPane: CoachPane?` and `@State private var seenReceipts: Set<String>?`. Observe the latest exchange only when `coach.timeline?.window.isLatest(turn.id) == true`; on each change call `CoachPane.landing(seen:receipts:activeDayID:modalOpen:)` with `modalOpen` = the key window's `rootViewController?.presentedViewController != nil`; if `jumps`, set `coachPane`, and post `AccessibilityNotification.Announcement` naming where it went without moving focus. Always union the receipt keys into `seenReceipts` afterwards, including on the first observation and when a jump was skipped. Reset `coachPane = nil` when `coach.diary.selection` changes (this replaces `selectedRecord = nil` at `CoachView:191`).
- [ ] **Step 7: Wire the tab.** `DuoBeside(secondaryLeading: true) { NavigationStack { CoachView(…, pane: $coachPane) } } secondary: { CoachSidePane(model: model, companionRuntime: companionRuntime, pane: $coachPane) }`.
- [ ] **Step 8: Run `MivuUITests/DuoLayoutUITests`, `MivuTests/CoachPaneTests`, `MivuTests/DuoLayoutTests` and `MivuUITests/CoachNavigationUITests`.** Expected: all pass; skips only for window-shape guards.
- [ ] **Step 9: Commit** `feat(duo): open Coach results beside the chat, chat on the right`.

### Task 4: Verify PR 1 on the Duo simulator and open it

**Files:**
- Create: `docs/verification/2026-11-14-coach-open-screen.md`
- Modify: `README.md:57-58` (the "Unfolded and sideways" bullet: results open beside the chat, chat on the right)

- [ ] **Step 1: Drive the Duo simulator** (Device Hub poses, on-screen keyboard) and record a screenshot per line into `docs/verification/coach-open-screen/`:
  - sideways flat and book: pane left, chat right, both meet the crease in book;
  - type a draft, open a meal in the pane, rotate upright (meal is pushed over the chat, draft intact), rotate back (meal in the pane, chat at the same position);
  - open a meal while closed, unfold and turn sideways: it is in the pane;
  - Coach logs to another day → pane shows that day; Coach logs a weight → pane shows Progress with no Pip;
  - with a meal open in the pane, ask Coach to correct it → the detail updates in place;
  - with an edit sheet open in the pane, let a queued Coach change commit → pane unchanged, edit intact;
  - switch profile with a meal open in the pane → pane on Today;
  - table pose unchanged; accessibility text size sideways behaves as upright;
  - VoiceOver: the automatic jump is announced and focus stays in the chat;
  - all four tabs through all rotations, CPU back to idle each time.
- [ ] **Step 2: Write the verification note:** source SHA, simulator and runtime, named test counts, the checklist results, anything blocked.
- [ ] **Step 3: Commit** `docs(duo): record Coach side pane verification`, push, open the PR, run Ponytail Review, fix blocking findings, verify CI.

### Task 5: Expand the pane to full screen

**Files:**
- Modify: `ios/Mivu/Design/DuoLayout.swift`, `ios/Mivu/Coach/CoachSidePane.swift`, `ios/Mivu/Diary/TodayView.swift` (Coach tab)
- Test: `ios/MivuUITests/DuoLayoutUITests.swift`

**Interfaces:**
- Consumes: `DuoBeside(secondaryLeading:)`, `CoachSidePane` (Task 3).
- Produces: `DuoBeside(secondaryLeading:secondaryFills: Bool = false)`; `CoachSidePane(..., expanded: Binding<Bool>)`; button identifiers `coachPaneExpand` (label "Expand") and the same button labelled "Show chat" when expanded.

When `secondaryFills && isWide`: the primary stays mounted with zero width, hidden from hit testing and accessibility; the crease gap is dropped; the secondary gets `isWideLayout = true` so Today and Progress use their own sideways columns and crease rules. Expanding dismisses the keyboard. When not wide the flag is ignored.

- [ ] **Step 1: Write the failing UI test.**

```swift
func testSidewaysPaneExpandsAndCollapses()
// type "draft text" in coachInput; tap coachPaneExpand →
//   coachSidePane.frame.width >= window.width - 1, coachInput is not hittable,
//   todaySummaryColumn and todayMealsColumn both exist;
// tap coachPaneExpand again → coachInput.value == "draft text", pane left of chat.
```

- [ ] **Step 2: Run it.** Expected: FAIL (`coachPaneExpand` not found).
- [ ] **Step 3: Implement** `secondaryFills`, the toolbar button on the pane's root and on its pushed destination (SF Symbols `arrow.up.left.and.arrow.down.right` / `arrow.down.right.and.arrow.up.left`, 44-point target), and `@State private var coachPaneExpanded = false` in `DiaryRootView`, reset with `coachPane` on profile change.
- [ ] **Step 4: Run `MivuUITests/DuoLayoutUITests`.** Expected: all pass.
- [ ] **Step 5: Duo simulator check,** appended to the verification note: expand in flat and book (columns meet the crease), rotate upright while expanded (normal upright app), back sideways, chat position and draft intact, CPU idle.
- [ ] **Step 6: Commit** `feat(duo): expand the Coach side pane to full screen`, PR, Ponytail Review, CI.

### Task 6: Diary in two columns sideways

**Files:**
- Modify: `ios/Mivu/Diary/HistoryView.swift:45-85,195-…` (`body`, `DaySections`), `ios/Mivu/Diary/TodayView.swift:381`
- Test: `ios/MivuUITests/DuoLayoutUITests.swift`

**Interfaces:**
- Produces: `DaySections(model:dayID:title:part:)` with `enum Part { case all, summary, records }` (default `.all`); column identifiers `diarySummaryColumn`, `diaryRecordsColumn`.

Sideways (`isWideLayout`): `DuoSplit { list(week strip, load error, saved receipt, loading, empty state, each day's .summary) } secondary: { list(each day's .records) }`, each list scrolling alone, same list styling as now. Otherwise the current single list with `.all`. The Diary tab drops `evenWhenWide: true`.

- [ ] **Step 1: Replace `testSidewaysDiaryKeepsReadableWidth`** with:

```swift
func testSidewaysDiarySplitsSummaryAndRecords()
// open the Diary tab; diarySummaryColumn.frame.maxX <= diaryRecordsColumn.frame.minX + 1;
// the week strip is inside diarySummaryColumn; a meal row is inside diaryRecordsColumn.
func testUprightDiaryStaysOneColumn()
// upright window: diaryRecordsColumn does not exist.
```

- [ ] **Step 2: Run them.** Expected: FAIL (`diarySummaryColumn` not found).
- [ ] **Step 3: Implement** the `Part` split and the sideways body.
- [ ] **Step 4: Run `MivuUITests/DuoLayoutUITests` and `MivuUITests/DiaryUITests`.** Expected: all pass.
- [ ] **Step 5: Duo simulator check,** appended to the note: flat, book (columns meet the crease), table and upright; another day shown in the Coach pane stays one column, and two columns when the pane is expanded; CPU idle.
- [ ] **Step 6: Commit** `feat(duo): two-column Diary when sideways`, PR, Ponytail Review, CI.

### Task 7: Half width beside another app

**Files:**
- Modify: only what the check finds broken.
- Modify: `docs/verification/2026-11-14-coach-open-screen.md`

- [ ] **Step 1: Put Mivu in system Split View** beside Safari on the Duo simulator, on each side in turn. If the simulator cannot do this, write "blocked: simulator cannot split two apps" in the note with the checklist below for the owner to run on their Duo, and stop this task. Do not count it as passed.
- [ ] **Step 2: Check and record each item:** all four tabs render the phone layout with no clipped content; Coach composer with the on-screen keyboard stays visible and sends; camera and photo picker open and return; a sheet and an alert present inside Mivu's half; "Jump to latest" drags and taps; resizing to full screen and back keeps the draft and chat position; system controls sit on Mivu's outer edge without covering content.
- [ ] **Step 3: For each small failure,** write a failing test where one can express it, fix it, and rerun the named test. If a screen needs a redesign, stop and report it instead of fixing it here.
- [ ] **Step 4: Commit** `fix(duo): keep Mivu usable at half width beside another app` (or a docs-only commit if nothing broke), PR, Ponytail Review, CI.
