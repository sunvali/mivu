# Coach model switch: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let people see and change the ChatGPT model (or Apple on-device) from the Coach title, or by asking Coach.
Remember the choice per account and move people up within their model family.

**Architecture:** A pure resolver (`ModelChoice`) decides which slug to use from the account catalog, the remembered
choice and the remote default family. `ChatGPTConnection` stores the choice per registration and publishes a
session-only `modelNotice`. `CoachView` shows the title menu and the notice. The Coach `set_model` tool queues a change
that the worker applies after the turn finishes, so a turn is never cut off by its own switch.

**Tech stack:** Swift 6, SwiftUI (iOS 26 `navigationSubtitle`, `toolbarTitleMenu`), Swift Testing, XcodeBuildMCP.

**Spec:** `docs/superpowers/specs/2026-11-20-coach-model-switch-design.md`

## Global constraints

- The catalog comes only from `ResponsesClient.models`. Never select or send a slug that is not in `connection.models`.
  Keep the `canCapture` and `respondForCoach` checks.
- Session-only UI (the notice and its Undo) never writes to the diary database and never counts toward the
  100-exchange window.
- Store data in `UserDefaults` (`DiaryLaunch.defaults`, which `ChatGPTConnection.preferences` already uses). Keys:
  `modelChoice.<registrationID>` (JSON `ModelChoice`) and `coachModelFamily` (String from `app-config.json`).
- 44-point targets, Dynamic Type, VoiceOver labels, and reduced motion for the notice transition.
- New strings use `String(localized:)`. They are English for now; Spanish and Russian fall back to English.
- Commits use Conventional Commit titles and never mention tooling.

## Review focus

1. **Go-style catalog** (one model, no Sol or Astra): no menu, the name is shown, and capture works. Covered by tests
   in Task 1 and Task 2.
2. **The remembered family leaves the catalog** (a downgrade): fall back to `catalog.first` and forget the choice.
   Task 1.
3. **Names that do not parse** ("o4-mini", "GPT-6.2"): keep that exact model and never upgrade it. Task 1.
4. **Asking Coach to switch mid-turn** must not trigger the `selectedModel == model` validation failure in
   `respondForCoach`. Task 4 applies the change only after `run` returns.
5. **Config missing, unfetchable, or naming a family the account lacks:** use `catalog.first`. Task 1 and Task 2.

---

### Task 1: `ModelChoice` resolver

**Files:**
- Create: `ios/Mivu/Connection/ModelChoice.swift`
- Test: `ios/MivuTests/ModelChoiceTests.swift`

**Interfaces (produces):**
```swift
struct ModelChoice: Codable, Equatable, Sendable {
    var slug: String
    var family: String?          // nil = name did not parse; exact pin, never upgraded
    var declinedSlug: String?    // set by Undo of an upgrade
}
enum ModelFamily {
    /// "GPT‑6.2 Sol" (any hyphen) → ("sol", [6, 2]); "GPT-6.2" → ("", [6, 2]); "o4-mini" → nil.
    static func parse(_ displayName: String) -> (family: String, version: [Int])?
    struct Resolution: Equatable { let slug: String; let choice: ModelChoice?; let upgradedFrom: String? }
    static func resolve(_ catalog: [AvailableModel], remembered: ModelChoice?, defaultFamily: String?) -> Resolution
}
```

**Rules for `resolve`.** These are the algorithm, so the order matters.
1. If the catalog is empty, return slug `""` with the choice unchanged.
2. If `remembered` is nil: take the newest model in `defaultFamily` (case-insensitive) if one is listed, otherwise
   `catalog.first`. Return choice nil and do not upgrade.
3. If `remembered.family` is nil: if its slug is listed, keep it; otherwise use `catalog.first` with choice nil.
4. If the family is set but no listed model is in it: use `catalog.first` with choice nil (forget it).
5. Otherwise take the newest model in the family by numeric version. Stay on `remembered.slug` when either:
   - the newest is the remembered slug, or
   - the newest is `declinedSlug` and `remembered.slug` is still listed.

   Otherwise upgrade: `upgradedFrom = remembered.slug`, choice slug = the newest, `declinedSlug = nil`. If
   `remembered.slug` is no longer listed but the family is, move to the newest model in the family with no note.

- [ ] **Step 1: Write failing tests** in `ModelChoiceTests` using the synthetic catalogs `[6.1 Sol, 6.2 Sol, 6.2 Astra]`,
  `[6.2 Go]` and `[]`:
  - `parsesFamilyAndVersion`: covers "GPT‑6.2 Sol", "GPT-6.2 Sol Mini" → "sol mini", "GPT-6.2", and "o4-mini" → nil.
  - `newcomerGetsDefaultFamilyNewest`: default "Sol" → `6.2 Sol`.
  - `missingDefaultFamilyUsesFirst`: default "Astra" on `[6.2 Go]` → `6.2 Go`.
  - `upgradesWithinFamilyOnly`: remembered 6.1 Sol → 6.2 Sol with `upgradedFrom` set; remembered 6.2 Astra stays.
  - `declinedUpgradeHoldsUntilNewer`: declined 6.2 Sol keeps 6.1; once a 6.3 Sol is added it upgrades.
  - `lostFamilyForgets`: remembered Astra on `[6.2 Go]` → `6.2 Go`, choice nil.
  - `unparsedNamePinsExactly`.
  - `emptyCatalog`.
- [ ] **Step 2:** Run with XcodeBuildMCP `test_sim -only-testing:MivuTests/ModelChoiceTests`. Expect it to fail to
  compile.
- [ ] **Step 3:** Implement `ModelChoice.swift` following the rules above.
- [ ] **Step 4:** Run again. Expect all tests to pass, with a non-zero count.
- [ ] **Step 5:** Commit with the message `feat(connection): resolve model choice by family`.

### Task 2: Connection remembers the choice, upgrades, and notices

**Files:**
- Modify: `ios/Mivu/Connection/ChatGPTConnection.swift`:
  - `loadModels`, the two `if !catalog.contains(where: { $0.slug == selectedModel })` lines (around 269 and 295).
  - Add the new API below.
- Modify: `ios/Mivu/Diary/AppUpdate.swift`. Change `Config` to `{ let ios: String?; let coachModelFamily: String? }`,
  then in `check` call `defaults.set(config.coachModelFamily, forKey: "coachModelFamily")`.
- Modify: `ios/Mivu/Diary/SettingsView.swift:317`. Bind the Picker as
  `Binding(get: { connection.selectedModel }, set: { connection.choose($0) })`.
- Test: `ios/MivuTests/ConnectionTests.swift` and `ios/MivuTests/AppUpdateTests.swift`.

**Interfaces (produces):**
```swift
struct ModelNotice: Equatable { enum Kind { case changed, upgraded, reanswering }
    let kind: Kind; let from: String; let to: String; let undoSlug: String? }   // names are display names
// ChatGPTConnection:
private(set) var modelNotice: ModelNotice?
func choose(_ slug: String, announce: Bool = false)   // explicit pick; ignores unlisted slugs; sets provider = .chatGPT
func undoModelChange()                                 // restores undoSlug; after an upgrade, stores declinedSlug
func noteReanswering()                                 // sets kind .reanswering for the current model
func dismissModelNotice()
var selectedModelName: String? { models.first { $0.slug == selectedModel }?.displayName }
```
- `choose` saves `ModelChoice(slug:, family: ModelFamily.parse(name)?.family, declinedSlug: nil)` under
  `modelChoice.<activeRegistrationID>`. It sets `modelNotice` only when `announce` is true (Coach-originated).
- After the catalog loads, the method calls `ModelFamily.resolve` with the saved choice and
  `preferences.string(forKey: "coachModelFamily")`. It saves or removes the returned choice and sets `selectedModel`.
  When `upgradedFrom` is set, it also sets `modelNotice = .upgraded` with `undoSlug = upgradedFrom`.
- The upgrade timing (my call): `TodayView` re-answers on a `selectedModel` change. If `coach.isWorking` is true when
  the catalog resolves, the existing behavior holds, which is acceptable because catalogs load at connect and at
  foreground, not during a turn. Do not add extra deferral code. Note this as a shortcut comment.

- [ ] **Step 1: Write failing tests.**
  - `choiceIsRememberedPerRegistration`: choose `second-model`, build a new connection on the same defaults, restore,
    and expect `selectedModel == "second-model"`.
  - `upgradeSetsNoticeAndUndoHoldsBack`: use a fixture catalog with two versions of one family.
  - `goCatalogSelectsOnlyModelAndCanCapture`.
  - `AppUpdateTests.storesCoachModelFamily`: config JSON `{"ios":"1.0","coachModelFamily":"Sol"}` stores "Sol", and
    the key being absent clears it.

  Extend the synthetic catalog fixture in `ConnectionTests` the same way it already serves `fixture-model` and
  `second-model`.
- [ ] **Step 2:** Run the `ConnectionTests` and `AppUpdateTests` suites. Expect failures.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `ConnectionTests`, `AppUpdateTests` and `CoachConnectionTests`. All should pass.
- [ ] **Step 5:** Commit with the message `feat(connection): remember model per account and follow its family`.

### Task 3: Coach title menu and notice

**Files:**
- Modify: `ios/Mivu/Coach/CoachView.swift:130`, where `.navigationTitle("Coach")` is set.
- Modify: `CoachView` `composerStack`, to place the notice above the field.

**Behavior:**
- **Subtitle:**
  - If `provider == .apple`: "Apple · on this iPhone".
  - Else if `planAuthorized` and `selectedModelName` is set: that name.
  - Otherwise no subtitle.
- **`.toolbarTitleMenu`**, only when there are at least two choices in total (ChatGPT models plus Apple when
  `appleAvailable`):
  - Section "ChatGPT": a `Button` for each model. Show `checkmark` on the current one when the provider is ChatGPT.
    The action records `let busy = coach.isWorking`, calls `connection.choose(slug)`, then
    `if busy { connection.noteReanswering() }`.
  - Section "On this iPhone": a `Button("Apple")` that sets `connection.provider = .apple`.
- **Notice:** a glass capsule above the composer showing `modelNotice`. Copy:
  - `.changed`: "Now using \(to)".
  - `.upgraded`: "Now using \(to) (was \(from))".
  - `.reanswering`: "Switched to \(to) · answering again".

  Show an Undo button (44 pt) when `undoSlug != nil`, plus a close button. Dismiss on send, Undo or close. Post
  `AccessibilityNotification.Announcement` when it appears. Use an opacity transition, with no motion under reduced
  motion.
- **Verify:** test that `toolbarTitleMenu` opens from the `.inlineLarge` title on iOS 26. If it doesn't, place a
  `Menu` labeled with the model name in `ToolbarItem(placement: .principal)` instead. Record which one was used.

- [ ] **Step 1: Write a failing UI test.** In `ios/MivuUITests/CoachNavigationUITests.swift`, add `modelTitleMenu`
  using a launch-argument fixture that sets two synthetic models. Assert that the subtitle text exists, that tapping
  it shows both names, and that choosing the second changes the subtitle. Add the fixture flag next to the existing
  `DiaryLaunch.isUITest` fixtures in `ChatGPTConnection` (DEBUG only).
- [ ] **Step 2:** Run that one UI test. Expect a failure.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the UI test plus `python3 scripts/ci/smoke.py --simulator-id <reserved-UUID>`. Both should pass.
  Take light and dark screenshots of the menu open, the one-model state and the notice.
- [ ] **Step 5:** Commit with the message `feat(coach): switch model from the Coach title`.

### Task 4: Ask Coach to switch

**Files:**
- Modify: `ios/Mivu/Coach/CoachTools.swift`. Add `CoachClarification.model` with the question "Which model should
  Coach use?". Add `CoachCommand.setModel(String)`. Add the `set_model` declaration and parse it.
- Modify: `ios/Mivu/Coach/CoachEngine.swift`. Add the init parameter
  `chooseModel: @escaping @Sendable (String) async -> String = { _ in #"{"changed":false,"reason":"unavailable"}"# }`.
  In the command switch, handle `case .setModel(let name): outputs[index] = await chooseModel(name)`.
- Modify: `ios/Mivu/Coach/CoachViewModel.swift`. Wire `chooseModel` in the `CoachEngine(...)` call (around line 500)
  and add `private var pendingModel: String?`. After `.run(...)` returns successfully, call
  `if let slug = pendingModel { pendingModel = nil; connection.choose(slug, announce: true) }`.
- Test: `ios/MivuTests/CoachEngineTests.swift`.

**`set_model` tool description (exact text):**
"Switch which ChatGPT model answers from the next message on, only when the person asks to change models. Pass the
model's name as they said it. If the result says changed false, call ask_clarification alone with kind model and
options set to the available names it lists. Never claim a switch unless the result says changed true."

**Matching rule for `chooseModel` (MainActor, in CoachViewModel):**
1. "apple" matches case-insensitively when `appleAvailable` is true. It sets `connection.provider = .apple` after the
   turn, in the same deferred way.
2. Otherwise, an exact case-insensitive match on display name or slug.
3. Otherwise, a family match from `ModelFamily.parse` against the asked name or a single family word ("astra"),
   choosing the newest model in that family.
4. If nothing matches, return `{"changed":false,"available":[names]}`. If something matches, queue it and return
   `{"changed":true,"model":"<display name>","applies":"next message"}`.

- [ ] **Step 1: Write failing tests** with the scripted inference fixtures already used in `CoachEngineTests`:
  - `setModelToolReportsChangeAndReplies`: the tool result is passed to the next round and the turn completes.
  - `unknownModelLeadsToModelClarification`: the scripted model calls `ask_clarification` with kind `model` and
    options. The finished turn's question has kind `.model` and those options.
  - A `CoachViewModel`-level test that the pending model is applied only after the turn completes, so
    `selectedModel` stays unchanged during the inference rounds.
- [ ] **Step 2:** Run the `CoachEngineTests` suite. Expect failures.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `CoachEngineTests`, `CoachConnectionTests` and `ModelChoiceTests`. All should pass.
- [ ] **Step 5:** Commit with the message `feat(coach): switch model when asked in chat`.

### Task 5: Verify and install on the Duo

- [ ] Run the focused suites from Tasks 1–4 and the smoke test. Record the SHA, simulator and test counts.
- [ ] Run the `ux-ui-reviewer` on the Task 3 screenshots and the `senior-qa` agent on the branch. Fix any blocking
  findings.
- [ ] Install on the owner's iPhone Duo with:
  `xcodebuildmcp device build-and-run --project-path ios/Mivu.xcodeproj --scheme Mivu --device-id 00008160-001C25CC14600036 --configuration Debug --extra-args="DEVELOPMENT_TEAM=3WEZAZAG65" --extra-args="-allowProvisioningUpdates"`.
  Do not commit the team ID.
- [ ] On the device, with the owner's real connection, read the real model display names to confirm the parse
  assumption. Report the result.
