# Language-ready (step 1 of many languages) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every piece of Mivu's iOS text translatable and every screen correct in right-to-left, with no visible change for today's English users.

**Architecture:** Remove the forced English locale and ship English as the only bundled language, so the system resolves language, direction and formatting together. All text a person reads goes through the string catalogs (SwiftUI literal keys, `String(localized:)` elsewhere, the English text is the key). A UI sweep test proves it with the system's double-length and right-to-left launch flags, on iPhone and iPhone Duo.

**Tech Stack:** Swift 6, SwiftUI/UIKit, String Catalogs (`.xcstrings`), XCUITest, Python 3 for the hosted lint. Builds and tests run through XcodeBuildMCP; the `xcodebuild` lines below are the equivalent commands.

**Spec:** `docs/superpowers/specs/2026-11-14-languages-design.md`. Steps 2 and 3 of the spec get their own plans after this one merges.

## Global Constraints

- English wording does not change, except to fix a visibly wrong plural ("1 servings"). List each such fix in its pull request.
- Stored and model-facing values never localize: dates as `yyyy-MM-dd`, numbers, record types, tool names, tool arguments, tool outputs, prompts, CSV values, log messages. They keep `en_US_POSIX`.
- No change to the diary schema, the archive format or profile validation. `["en", "he"].contains(profile.language)` stays as is.
- No layout code may test for a language by name. Use leading/trailing and the environment's layout direction.
- Charts over time, Pip's artwork, photos and the camera do not mirror. Everything else does.
- Hebrew is not shown to users in this step.
- The week keeps starting on the day it does today. Digits are 0–9.
- Follow `AGENTS.md`: failing test first, feature branches, Conventional Commit titles, no mention of AI tools, XcodeBuildMCP for native work, targeted tests only, record the exact source SHA.
- Each pull request below is reviewed with Ponytail Review before merge.

**The localization rule every task applies:**

| Text | What to do |
|---|---|
| Literal passed to `Text`, `Label`, `Button`, `Toggle`, `Section`, `.navigationTitle`, `.alert`, accessibility modifiers | Already a catalog key. Leave the code; make sure the key is in the catalog. |
| `String` a person reads, built outside a view (view models, notifications, Siri dialog, receipts, Pip's lines, errors, report headings) | `String(localized: "English text")`. Keep the type `String`. |
| Sentence glued from parts (`"Remove the whole" + names + "meal?"`) | One string with placeholders: `String(localized: "Remove the whole \(names) meal?")`. |
| Count next to a noun | One key with plural variations in the catalog (`%lld meals`: one / other). |
| Unit words shown to people (`kcal`, `g`, `kg`) | Part of a translatable format: `"\(value) kcal"`. |
| Date pattern shown to people (`"EEEE d MMMM"`) | `String(localized: "EEEE d MMMM", comment: "Date pattern: weekday, day, month")`, formatter locale `.current`. English output stays identical; each language orders its own. |
| `String(format:)` or a fixed-locale formatter whose result a person reads | `.formatted()` or a formatter with `Locale.current`, unless a row above or a task says it stays fixed. |
| Text the model reads, text that is stored as data, log text, test fixtures (`CoachUITestInference`, `*UITestFixture`), debug-only screens (`PipRigPreview`, `ConnectionProofView` when debug-only) | Leave as a plain literal. |
| A comparison of a displayed string (`label == "Unknown"`) | Compare the underlying value instead. |

## Review Focus

1. **Hebrew phone, English-only build:** the app is all English, left-to-right, with English dates and numbers (never Hebrew month names beside English text). Test in Task 2.
2. **Hebrew or Arabic typed into an English app** (message, food name, profile name): the text aligns by its own direction, numbers beside it keep their order, saved text is byte-identical. Test in Task 8.
3. **A model reply with non-ASCII digits** ("٧٤٠ kcal"): the number check reads them and rejects ungrounded ones instead of letting them through. Test in Task 9.
4. **Counts of 0 and 1:** "1 meal", "0 meals", "1 serving" read correctly. Test in Task 4.
5. **Longest text:** at double length and the largest text size, primary buttons stay reachable and tappable. Asserted by the sweep in Tasks 1 and 10.

---

## Pull request A: foundation

### Task 1: Language sweep test and English baseline

**Files:**
- Create: `ios/MivuUITests/LanguageSweepUITests.swift`
- Create: `docs/verification/languages/README.md` (how to run the sweep, where captures go)

**Interfaces:**
- Produces: `LanguageSweepUITests` with launch environment `SWEEP_MODE` = `english` | `rtl` | `double`, and `SWEEP_TEXT` = `default` | `largest`; a `static let notYetLocalized: Set<String>` of screen names that later tasks empty; `func visitAllScreens(_ body: (String, XCUIApplication) -> Void)`.

- [ ] **Step 1: Write the sweep test.** It launches with the same fixture arguments the existing suites use (`--diary-ui-test <uuid> --coach-ui-test --coach-inference-fixture`, see `CoachNavigationUITests.swift:128` and `DiaryUITests`), plus:
  - `rtl`: `-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES`
  - `double`: `-NSDoubleLocalizedStrings YES`
  - `largest`: `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`

  `visitAllScreens` walks, in order: `onboarding`, `today`, `diary`, `mealDetail`, `mealComposer`, `manualNutrition`, `progress`, `goalEditor`, `weightEditor`, `coach` (after one fixture turn that shows a saved-food card), `coachHistory`, `settings`, `backupSettings`. At each it attaches a screenshot named `<mode>-<text>-<screen>`.

  Tests:
  ```swift
  func testEveryScreenOpens()          // all modes: each screen's root identifier exists
  func testPrimaryActionsStayHittable() // rtl, double, largest: Log meal, Ask Pip, composer send, Save in each editor are isHittable
  func testTextIsLocalized()           // double only, see step 2
  ```

- [ ] **Step 2: `testTextIsLocalized`.** For every screen not in `notYetLocalized`, every `staticTexts`, `buttons` and `navigationBars` label must be doubled: the label equals `half + " " + half`. Skip labels with no letters and labels in `fixtureData` (food names, profile name, typed messages from the fixture). Start with every screen name in `notYetLocalized`.

- [ ] **Step 3: Prove the flag works.** Temporarily remove `today` from `notYetLocalized` and run in `double` mode.
  Run: `xcodebuild test -project ios/Mivu.xcodeproj -scheme Mivu -testPlan Mivu -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MivuUITests/LanguageSweepUITests/testTextIsLocalized`
  Expected: FAIL listing only Today's labels that are not localized, and the screenshot shows the tab labels doubled ("Today Today"). If nothing on screen is doubled, stop and report: the plan depends on this flag. Put `today` back.

- [ ] **Step 4: Capture the English baseline** on this commit before any app change: `english` mode, default and largest text, iPhone 17. Save the screenshots under `docs/verification/languages/baseline/`.

- [ ] **Step 5: Commit.** `test(ui): add the language sweep and its English baseline`

### Task 2: English is the only bundled language; remove the lock

**Files:**
- Create: `scripts/ci/languages.py`, `scripts/ci/test_languages.py`
- Create: `docs/languages/he-legacy.json`
- Modify: `ios/Mivu/Localizable.xcstrings`, `ios/Mivu/InfoPlist.xcstrings`, `ios/Mivu.xcodeproj/project.pbxproj:298-302`, `ios/Mivu/Mivu.xctestplan`
- Modify: `ios/Mivu/MivuApp.swift:9-10` and the forced pairs at `CoachView.swift:136`, `ManualNutritionView.swift:125`, `MealComposerView.swift:111-112`, `MealDetailView.swift:510,640-641`, `SettingsView.swift:101-102,299-300`, `ProgressEditorViews.swift:251-252,403-404,613-614,757-758`
- Test: `ios/MivuUITests/LanguageSweepUITests.swift`, `scripts/ci/test_languages.py`

**Interfaces:**
- Produces: `python3 scripts/ci/languages.py check` (exit 0 when clean) and `python3 scripts/ci/languages.py xliff <path-to-en.xliff>`.

- [ ] **Step 1: Write `test_languages.py`** in the style of `test_parity.py`:
  ```python
  def test_language_outside_known_regions_fails(): ...   # catalog has "he", pbxproj lists only en → error names the language
  def test_missing_translation_fails(): ...              # a listed language lacks one key → error names the key
  def test_missing_plural_form_fails(): ...              # plural variation lacks "other" → error
  def test_stale_key_fails(): ...                        # extractionState "stale" → error
  def test_clean_catalogs_pass(): ...
  def test_xliff_key_missing_from_catalog_fails(): ...   # exported source key not in catalog → error names the key
  ```
- [ ] **Step 2: Run** `python3 -m pytest scripts/ci/test_languages.py`. Expected: FAIL, module not found.
- [ ] **Step 3: Implement `languages.py`.** The shipped languages are `knownRegions` in `project.pbxproj` minus `Base`. `check` reads every tracked `*.xcstrings` under `ios/`. Keys with `shouldTranslate: false` are skipped. Wire `check` into the hosted script checks where `parity.py` is invoked.
- [ ] **Step 4: Move Hebrew out.** Write every existing Hebrew value to `docs/languages/he-legacy.json` as `{ "<catalog file>": { "<key>": "<Hebrew>" } }`, delete the `he` localizations from both catalogs, and remove `he` from `knownRegions`.
- [ ] **Step 5: Pin tests to English.** Add `"language": "en", "region": "US"` to `defaultOptions` in `Mivu.xctestplan`.
- [ ] **Step 6: Write the failing lock tests** in `LanguageSweepUITests`:
  ```swift
  func testRightToLeftFlagMirrorsTheApp()
  // rtl mode: the Today tab's frame.midX > the Coach tab's frame.midX
  func testHebrewPhoneGetsEnglish()
  // launch with -AppleLanguages (he) -AppleLocale he_IL:
  // tab labels are "Today", "Diary", "Progress", "Coach"; Today tab midX < Coach tab midX;
  // the Diary day title contains an English month name
  ```
- [ ] **Step 7: Run both.** Expected: `testRightToLeftFlagMirrorsTheApp` FAILS (the lock holds the app left-to-right).
- [ ] **Step 8: Delete every forced `.environment(\.locale, Locale(identifier: "en"))` and `.environment(\.layoutDirection, .leftToRight)`** listed above. Do not replace them with anything.
- [ ] **Step 9: Run** the two lock tests, `testEveryScreenOpens` in `english` mode, and `python3 scripts/ci/languages.py check`. Expected: PASS. Confirm the built `Mivu.app` contains no `he.lproj`.
- [ ] **Step 10: Compare** a fresh `english` capture set with the Task 1 baseline. Expected: identical layout on every screen. Record any difference in the pull request.
- [ ] **Step 11: Commit.** `refactor(app): bundle English only and follow the system language`

Open pull request A. Note in it that a Hebrew phone now sees the camera permission text in English.

---

## Pull requests B to F: move text into the catalogs

Tasks 3 to 7 share one shape. For the task's files:

- [ ] **Step 1:** Remove the task's screens from `notYetLocalized`. Run `testTextIsLocalized` in `double` mode. Expected: FAIL listing the labels that are not localized.
- [ ] **Step 2:** Apply the localization rule table to every file in the task. Add the task's unit tests (listed per task) and see them fail where they cover new behaviour.
- [ ] **Step 3:** Export and reconcile the catalog:
  `xcodebuild -exportLocalizations -project ios/Mivu.xcodeproj -localizationPath "$TMPDIR/mivu-loc" -exportLanguage en`, then `python3 scripts/ci/languages.py xliff "$TMPDIR/mivu-loc/en.xcloc/Localized Contents/en.xliff"`. Add every reported key to the right catalog, with plural variations where the key has a count. Expected: exit 0.
- [ ] **Step 4:** Run `testTextIsLocalized` (double), `testEveryScreenOpens` (english), the task's unit tests and the existing suites named in the task. Expected: PASS, with English strings unchanged.
- [ ] **Step 5:** Search the task's files for `== "` and `.contains("` against displayed strings; switch each to the underlying value.
- [ ] **Step 6:** Commit and open the task's pull request.

### Task 3: Coach

**Files:** `ios/Mivu/Coach/` views and view models (`CoachView`, `CoachReceiptView`, `CoachCameraView`, `CoachHistoryView`, `CoachViewModel`, `CoachActivityView`, `CoachReplyQuote`, `CoachVoiceInput`, `PipLine`, `CoachReplyLines`, `CoachManualEdits`), plus person-facing strings in `CoachEngine.swift` (clarification questions near lines 136–146, `CoachClarification.question`) and the committed and recorded summaries in `DiaryDatabaseQueries.swift`.
**Leave untouched:** `CoachTools.swift`, `CoachEngine.stableRules`, tool outputs, `failureReason`, `CoachUITestInference`, `CoachCorrectionUITestFixture`. The number format at `CoachReplyLines.swift:78` and `DiaryDatabaseQueries.swift:387` stays `en_US` (digits rule).
**Screens:** `coach`, `coachHistory`.
**Existing suites:** `CoachReplyTests`, `CoachEngineTests`, `PipLineTests`, `CoachNavigationUITests`.
**Unit test:** `CoachEngineTests.removeWholeMealQuestionIsOneSentence`: with item names "Rice, Beans" the question is exactly `"Remove the whole Rice, Beans meal?"`, and with no names it is `"Remove the whole meal?"` (two keys, no doubled space).
**Commit:** `refactor(coach): make Coach text translatable`

### Task 4: Today, Diary and meals

**Files:** `ios/Mivu/Diary/` `TodayView`, `HistoryView`, `DiaryWeekStrip`, `MealDetailView`, `MealComposerView`, `ManualNutritionView`, `MorningCheckInCard`, `DiaryStyle`, `DiaryViewModel`, `DiaryModels` (person-facing labels only), `PhotoCapture`, `QuickLogCameraView`.
**Screens:** `today`, `diary`, `mealDetail`, `mealComposer`, `manualNutrition`.
**Existing suites:** `DiaryUITests`, `ManualNutritionUITests`, `SummaryCardsUITests`.
**Unit tests** in a new `ios/MivuTests/LanguagePluralTests.swift`:
```swift
@Test func mealCountsReadCorrectly() // pillLabel for 0, 1, 2 meals contains "0 meals", "1 meal", "2 meals"
@Test func servingCountsReadCorrectly() // the amount label for 1 and 2 reads "1 serving", "2 servings"
@Test func dayTitleKeepsItsEnglishShape() // DiaryWeekStrip.format("2026-10-19", pattern for the day title) == today's exact English output
```
`DiaryWeekStrip.format` changes its signature to take the pattern as a `String` produced by `String(localized:)` and uses `Locale.current`.
**Commit:** `refactor(diary): make Today, Diary and meal text translatable`

### Task 5: Progress

**Files:** `ios/Mivu/Progress/` all files. `ProgressAnalytics.swift:191,202` and `ProgressEditorViews.swift:20` keep POSIX when they produce stored date keys; switch to `.current` only where the result is shown.
**Screens:** `progress`, `goalEditor`, `weightEditor`.
**Existing suites:** `ProgressInsightsTests`, `ProgressUITests`.
**Extra:** wrap each `Chart` plot in `.environment(\.layoutDirection, .leftToRight)` so time runs left to right in every language; its title and legend stay outside the wrapper. Add `LanguageSweepUITests.testChartsDoNotMirror`: in `rtl` mode the first bar's `frame.minX` equals its value in `english` mode within 2 points.
**Commit:** `refactor(progress): make Progress text translatable`

### Task 6: Settings, onboarding and connection

**Files:** `ios/Mivu/Diary/SettingsView.swift`, `DiaryBackupSettings.swift`, `DiaryReportSettings.swift`, `DaySettingsSection.swift` (screen text), `ios/Mivu/Onboarding/`, `ios/Mivu/Connection/` person-facing notices and consent text, `ios/Mivu/Design/` accessibility labels.
**Screens:** `onboarding`, `settings`, `backupSettings`.
**Existing suites:** `SmokeUITests`, `RootTabNavigationUITests`, the onboarding tests in `DiaryUITests`.
**Commit:** `refactor(settings): make Settings, setup and connection text translatable`

### Task 7: Text outside the app's screens

**Files:**
- Notifications: `CoachReplyNotification.swift`, `MealNotification.swift`, `DaySettingsSection.swift:80`.
- Siri and shortcuts: `TellCoachIntent.swift` (dialog at line 64), `QuickLog.swift`, `ios/Shared/MivuIntents.swift`. Create `ios/Mivu/AppShortcuts.xcstrings` for the phrases at `QuickLog.swift:22-26`.
- Widgets: `ios/MivuWidgets/*.swift`. Create `ios/MivuWidgets/Localizable.xcstrings` in the widget target; keys used by `ios/Shared/` go in both catalogs.
- Reports: headings in `DiaryReport.swift` and `DiaryReportPDF.swift`. CSV values and the formatters at `DiaryReport.swift:20,90` stay POSIX.
- `ios/Mivu/InfoPlist.xcstrings`: confirm all three keys are present.

**Screens:** none (no doubling assertion; these surfaces are outside the sweep).
**Unit tests:** extend the existing notification, `TellCoachTests`, widget snapshot and `DiaryReportTests` so each asserts today's exact English text still comes out. They pass before and after; they are the guard against wording drift.
**Check:** `python3 scripts/ci/languages.py check` covers all four catalogs.
**Commit:** `refactor(app): make notification, Siri, widget and report text translatable`

---

## Pull request G: direction and mixed text

### Task 8: Mirroring fixes and text that carries its own direction

**Files:**
- Create: `ios/Shared/TextDirection.swift`, `ios/MivuTests/TextDirectionTests.swift`
- Modify: the eight directional symbol uses (`git grep -n -e 'chevron\.\(left\|right\)' -e 'arrow\.\(left\|right\)' -e 'arrow.uturn' -- ios`), the two `offset(x:)`/`rotationEffect` sites, `CoachTimelineView.swift` and its cells, `CoachReceiptView.swift`, meal and food name labels in `TodayView`, `HistoryView`, `MealDetailView`.

**Interfaces:**
- Produces:
  ```swift
  enum TextDirection {
      /// Direction of the first letter; nil when the text has no letters.
      static func of(_ text: String) -> LayoutDirection?
  }
  extension View {
      /// Lays this text out by its own content, falling back to the surrounding direction.
      func directionFromContent(_ text: String) -> some View
  }
  ```

- [ ] **Step 1: Write the failing tests.**
  ```swift
  @Test func directions() {
      #expect(TextDirection.of("סלט עוף") == .rightToLeft)
      #expect(TextDirection.of("سلطة") == .rightToLeft)
      #expect(TextDirection.of("Chicken salad") == .leftToRight)
      #expect(TextDirection.of("200 g סלט") == .rightToLeft)   // first letter decides
      #expect(TextDirection.of("740") == nil)
      #expect(TextDirection.of("") == nil)
  }
  ```
- [ ] **Step 2: Run.** Expected: FAIL, `TextDirection` not found.
- [ ] **Step 3: Implement `TextDirection.of`.** Take the first scalar with `properties.isAlphabetic`. It is right-to-left when its value is in `0x0590...0x08FF`, `0xFB1D...0xFDFF` or `0xFE70...0xFEFF`. No language names, no language detection library.
- [ ] **Step 4: Apply `directionFromContent`** to every view that shows text a person typed or a model wrote: Coach user bubbles and replies, food and meal names, profile name, notes. In the UIKit timeline set `semanticContentAttribute` and text alignment from the same function.
- [ ] **Step 5: Symbols.** Replace `chevron.right`/`chevron.left` with `chevron.forward`/`chevron.backward`, `arrow.right`/`arrow.left` with the forward/backward names. Leave `arrow.uturn.backward` (Undo) as is. Fix the `offset(x:)` and `rotationEffect` sites only if the `rtl` captures show them wrong.
- [ ] **Step 6: Write the UI test** `LanguageSweepUITests.testTypedHebrewKeepsItsDirectionAndBytes`: in `english` mode send the Coach message `"צהריים: סלט עוף 200 g"`. The sent bubble's label equals the typed string exactly, and the bubble's text is right-aligned inside the bubble (its `frame.maxX` is within 24 points of the bubble's trailing edge). In `rtl` mode an English message is left-aligned by the mirror of the same rule.
- [ ] **Step 7: Walk the `rtl` captures** for every screen at default and largest text. Fix each element that fails the spec's mirroring list, using leading/trailing. Pip's rig view must not be flipped; its position mirrors.
- [ ] **Step 8: Run** the sweep in all three modes, `CoachNavigationUITests` (Jump to latest drag, tap and viewport restoration within 2 points), `CompanionUITests`. Expected: PASS.
- [ ] **Step 9: Commit.** `feat(app): mirror layouts and align typed text by its own direction`

---

## Pull request H: Coach checks that work in any language

### Task 9: Number check reads any digits; save claims use a marker

**Files:**
- Modify: `ios/Mivu/Coach/CoachReplyCheck.swift`, `ios/Mivu/Coach/CoachEngine.swift:66-73,98-104,248`
- Test: `ios/MivuTests/CoachReplyTests.swift` (or the file that holds `CoachReplyCheck` tests), `ios/MivuTests/CoachEngineTests.swift`

**Interfaces:**
- Produces:
  ```swift
  extension CoachReplyCheck {
      static let saveMarker = "<saved/>"
      /// The prose without the marker, and whether the marker was present.
      static func splitSaveClaim(_ prose: String) -> (text: String, claimsSave: Bool)
  }
  ```
  `passes(_:allowed:receipts:)` gains a parameter `claimsSave: Bool`.

**Decisions (not in the spec; recorded here as the plan's calls):**
- The model is told, in `stableRules`: `End a reply with <saved/> on its own line if and only if the reply says something was saved, logged, updated, moved or deleted.` The engine strips the marker before checking, storing or showing the text.
- `claimsSave` is true when the marker is present **or** the existing English phrase lists match. The English lists stay as a second net so English behaviour cannot regress. Mark them: `// shortcut: English-only net beside the marker, remove once a live evaluation shows the marker alone holds.`
- The "edit … one more" wording at `CoachEngine.swift:143` stays English-only. In other languages the general clarification question is shown, which is correct and only less specific. Mark it with a `shortcut:` comment saying so.

- [ ] **Step 1: Write the failing tests.**
  ```swift
  @Test func readsDigitsInAnyScript() {
      #expect(CoachReplyCheck.numbers(in: "٧٤٠ kcal") == [740])
      #expect(CoachReplyCheck.numbers(in: "७४० kcal") == [740])
      #expect(CoachReplyCheck.numbers(in: "٧٣٫٦ كغ") == [Decimal(string: "73.6")!])
  }
  @Test func ungroundedForeignDigitsFail() {
      #expect(!CoachReplyCheck.passes("٧٤٠ kcal", allowed: [], receipts: [], claimsSave: false))
      #expect(CoachReplyCheck.passes("٧٤٠ kcal", allowed: [740], receipts: [], claimsSave: false))
  }
  @Test func markerIsStrippedAndReported() {
      let split = CoachReplyCheck.splitSaveClaim("נשמר.\n<saved/>\n")
      #expect(split.text == "נשמר.")
      #expect(split.claimsSave)
      #expect(!CoachReplyCheck.splitSaveClaim("Looks good.").claimsSave)
  }
  @Test func markerOnAnAwaitingReviewMealFails()   // receipts with one awaitingReview meal, claimsSave: true → passes == false
  ```
  In `CoachEngineTests`, using the existing inference fixture style:
  ```swift
  @Test func hebrewSaveClaimWithoutAReceiptIsRejected()
  // model text "שמרתי את הארוחה.\n<saved/>", no tool calls, no receipts → throws CoachError.ungroundedConfirmation
  @Test func markerNeverReachesStoredText()
  // model text "Logged.\n<saved/>" after a successful food receipt → stored assistantText has no "<saved/>"
  @Test func englishClaimWithoutMarkerIsStillRejected()
  // "I've saved your lunch." with no receipts → throws, exactly as today
  ```
- [ ] **Step 2: Run.** Expected: the digit, marker and Hebrew tests FAIL; the English one passes.
- [ ] **Step 3: Implement.** In `numbers(in:)`, map every character with a `wholeNumberValue` to its ASCII digit and `٫` to `.`, `٬` to `,` before matching; if a matched token still fails to parse, return a value that cannot be in `allowed` so the check fails closed. Implement `splitSaveClaim`, thread `claimsSave` through `CoachEngine.run` and `passes`, add the sentence to `stableRules`.
- [ ] **Step 4: Run** the new tests plus `CoachEngineTests`, `CoachReplyTests`, `CoachCorrectionJourneyTests`, `CoachReceiptFeedbackTests`. Expected: PASS.
- [ ] **Step 5: Commit.** `fix(coach): check reply numbers and save claims in any language`

Record in the pull request that the marker's live behaviour with the real model is not verified by fixtures; a live check belongs to the step 2 plan.

---

## Pull request I: recipe, rules and evidence

### Task 10: Documents and the full sweep on iPhone and Duo

**Files:**
- Create: `docs/development/adding-a-language.md`, `docs/verification/2026-11-languages-step1.md`
- Modify: `AGENTS.md`, `README.md` (the Hebrew sentence in the first paragraph), `docs/parity.md`

- [ ] **Step 1: Write `adding-a-language.md`:** the localization rule table from this plan; the steps to add a language (glossary under `docs/languages/`, translations in all four catalogs, the language in `knownRegions`, `languages.py check`, store text, the sweep); the review bar from the spec; that a language ships whole.
- [ ] **Step 2: Replace the English-only bullet in `AGENTS.md`** with:
  > - Mivu follows the system language and layout direction. English is the only bundled language until a language is complete on every surface. All text a person reads goes through the string catalogs; stored and model-facing values never localize. Follow [adding a language](docs/development/adding-a-language.md). Preserve existing profile/archive data and stored language values. Keep Dynamic Type, VoiceOver, reduced motion, and minimum 44-point touch targets.
- [ ] **Step 3: Add a `languages` row to `docs/parity.md`** (post-baseline, iOS `partial`, Android `pending`) and run `python3 scripts/ci/parity.py`. Expected: exit 0.
- [ ] **Step 4: Run the sweep matrix** on the merged step 1 source and save captures under `docs/verification/languages/step1/`:
  - iPhone 17: `english`, `rtl`, `double`, each at default and largest text.
  - iPhone Duo: `english`, `rtl`, `double` at default text in each pose (closed, open upright, open sideways, book, table); `rtl` at largest text in the closed pose. Drive the device with the T3 device tools, not `simctl`.
  The spec asks for largest text everywhere; on the Duo this plan narrows it to one pose to keep the run proportionate. Say so in the record.
- [ ] **Step 5: Compare** the `english` captures with the Task 1 baseline on iPhone, and with `docs/verification/iphone-duo/` on the Duo.
- [ ] **Step 6: Write the verification record:** source SHA, Xcode and runtime versions, result counts per suite, capture index, every difference found, and the blocked gates (fold and unfold with a draft, VoiceOver on a device, the marker with the live model).
- [ ] **Step 7: Commit.** `docs: record language readiness and the recipe for adding a language`

---

## Handed to the step 2 plan

- Decimal commas in model replies ("73,6 kg" in Spanish or Russian) against the number check.
- The reply-language instruction, the turn-language rule for receipts, the mic language switch.
- The mechanism that keeps Hebrew hidden once its translations are in the catalogs.
- Reusing `docs/languages/he-legacy.json`.
