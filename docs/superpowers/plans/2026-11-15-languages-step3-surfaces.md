# Languages step 3: everything around the app, and Hebrew on for users

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Widgets, Live Activity, Siri, notifications, the PDF and CSV reports and the App Store listing work in Hebrew, then Hebrew is switched on for users by removing it from `MIVU_HIDDEN_LANGUAGES`.

**Architecture:** The strings are already translated in all four catalogs (step 2). What's left is mostly layout and proof. The PDF is drawn at fixed x positions, so it needs a mirror helper. The morning reminder is scheduled once, so it needs rescheduling when the language changes. Settings needs a real Language row. The Hebrew store text and screenshots go in the repository. The switch-on is a one-line build setting change, done last, once every surface has proof.

**Tech Stack:** Swift 6, SwiftUI, WidgetKit, ActivityKit, App Intents, UserNotifications, UIGraphicsPDFRenderer, PDFKit (tests), String Catalogs, Swift Testing, XCTest UI tests, Python 3 (`scripts/ci/languages.py`).

**Spec:** [2026-11-14-languages-design.md](../specs/2026-11-14-languages-design.md), section "Step 3". Glossary: [he.md](../../languages/he.md). Step 2 record: [2026-11-15-languages-step2.md](../../verification/2026-11-15-languages-step2.md).

## Global Constraints

- "A language ships whole or not at all." `he` stays in `MIVU_HIDDEN_LANGUAGES` until Task 6, and Task 6 runs only after Tasks 1–5 have their proof.
- "Stored and model-facing values never localize." CSV numbers and dates stay in the fixed machine format; only CSV column headings are translated.
- "Charts over time keep time running left to right in every language." "Pip's artwork does not flip."
- "Digits are 0–9"; "Dates shown to people use the Gregorian calendar."
- English users see no change before Task 6. After it, the only English change is the Settings Language row (spec: "appears once Mivu ships more than one language").
- Uploading the listing to App Store Connect is the owner's action; this plan only prepares it in the repository.
- Hebrew wording follows `docs/languages/he.md`. Any new Hebrew string goes on the owner's review page before Task 6.
- Tests: targeted only, on my own "(Claude)" simulators. Record the exact SHA, the environment and the counts.
- Commits and PR: Conventional Commits, the owner's git identity, no mention of tools or assistants.

## Review Focus

1. **Morning reminder after a language change.** The repeating notification keeps the text it was scheduled with, so an English reminder would keep arriving after the phone switches to Hebrew. Expected: the next reminder after Mivu opens uses the new language. Task 2 tests it.
2. **PDF on a Hebrew phone with Hebrew hidden (Release before Task 6).** If the PDF mirrored based on `Locale.current`, English text would be laid out right to left. Expected: mirror only when the language actually shown is right to left (`Bundle.main.preferredLocalizations`). Task 1 tests it.
3. **Hebrew food names in an English PDF, and English food names in a Hebrew PDF.** Expected: each name draws in its own direction (`TextDirection.of`) inside its mirrored cell, and is not cut off on the wrong side. Task 1 tests it.
4. **Widget and Live Activity text at small sizes in Hebrew.** Hebrew strings are often longer ("קק״ל נרשמו"). Expected: nothing is cut off at the default text size in systemSmall, accessoryRectangular, or the compact Dynamic Island. Task 3 checks the captures.
5. **Siri phrases.** Expected: every Hebrew App Shortcut phrase contains `${applicationName}` and is unique across shortcuts, or Siri won't register it. Task 2 tests it.

---

### Task 1: PDF and CSV in Hebrew

**Files:**
- Modify: `ios/Mivu/Diary/DiaryReportPDF.swift`
- Modify: `ios/Mivu/Localizable.xcstrings` (only if `"%@ kcal"` is missing)
- Test: `ios/MivuTests/DiaryReportTests.swift`

**Interfaces:**
- Produces: `func pdfData(rightToLeft: Bool = DiaryReport.showsRightToLeft) -> Data` and `static var showsRightToLeft: Bool`, which is true when `Locale.Language(identifier: Bundle.main.preferredLocalizations.first ?? "en").characterDirection == .rightToLeft`.

- [ ] **Step 1: Write the failing tests.**
  - `pdfMirrorsForRightToLeft`: render `Self.range.pdfData(rightToLeft: true)` and read page 0 with PDFKit. Find the bounds of the `"Food log"` heading (`page.selection(for:)`, or find its string's characters). Assert its `minX > 297` (right half). With `rightToLeft: false`, assert `maxX < 297`.
  - `pdfDayTotalUsesTheKcalString`: the meal-page day total is built with `String(localized: "\(value) kcal")`. Assert the page text contains the same string the catalog gives for `"%@ kcal"`, not a hard-coded literal. If that can't be asserted from the PDF, assert it through a small `static func dayTotal(_:) -> String` that the drawing uses.
  - `pdfWeightChartDoesNotMirror`: with `rightToLeft: true`, the earliest weight point is still left of the latest. Expose the point mapping as `static func chartX(for:start:span:plot:) -> CGFloat` and test that.
  - `csvKeepsMachineDatesAndNumbers`: the CSV bodies contain no character in U+0590–U+05FF except in headings and food names; dates are `yyyy-MM-dd`; numbers use `.` as the decimal separator. This should pass today and guards the rule.
- [ ] **Step 2: Run** `-only-testing:MivuTests/DiaryReportTests -testPlan Mivu`. Expected: the first three fail. `summaryCountsEveryCalendarDayInTheRequestedRange` is a known failure on `main`; leave it.
- [ ] **Step 3: Implement.**
  - Inside `render`, a `place(_ rect: CGRect) -> CGRect` mirrors x (`page.width - rect.maxX`) when `rightToLeft` is true.
  - `draw` and the fills go through `place`, and `draw` swaps `.left` and `.right`.
  - Each cell's paragraph `baseWritingDirection` comes from `TextDirection.of(text)`, falling back to the page direction.
  - The weight polyline and its points are not placed through `place`.
  - The Pip image changes position only; the artwork is not flipped.
  - Replace the literal `"\(whole(day.totals.kcal)) kcal"` with the localized string.
- [ ] **Step 4: Run** the same tests. Expected: all pass except the known one.
- [ ] **Step 5: Generate the proof files.** In a Hebrew-mode Debug run, export a 7-day PDF and CSV from the sweep fixture and save them to the scratchpad. Look at every page. Attach page 1 and one meal page as PNGs to the record.
- [ ] **Step 6: Commit** `feat(reports): mirror the PDF for right-to-left languages`.

### Task 2: Notifications and Siri text follow the language

**Files:**
- Modify: `ios/Mivu/Diary/DaySettingsSection.swift` (`MorningReminder`)
- Modify: the app's launch or `scenePhase == .active` handler, wherever `MivuServices.start` runs
- Test: `ios/MivuTests/MealNotificationTests.swift`, `ios/MivuTests/CoachReplyNotificationTests.swift`, new `ios/MivuTests/HebrewSurfaceTextTests.swift`

**Interfaces:**
- Produces: `MorningReminder.refresh()`. If `enabledKey` is on, it calls `schedule(minutes:)` again with the stored minutes; otherwise it does nothing. Scheduling uses the same identifier, so it replaces the old request.
- Produces (tests only): `func hebrew(_ key: String) -> String`, which reads `Bundle.main.path(forResource: "he", ofType: "lproj")` and calls `localizedString(forKey:value:table:)`.

- [ ] **Step 1: Write the failing tests.**
  - `morningReminderRefreshesWhenEnabled`: with `enabledKey` on, `refresh()` leaves one pending request with id `"morning-check-in"` whose title equals `String(localized: "Good morning")`. With it off, there are no requests.
  - In `HebrewSurfaceTextTests`, `notificationAndSiriKeysHaveHebrew`: for each of these keys, `hebrew(key)` contains a letter in U+05D0–U+05EA:
    - "Good morning", "Log your weight or breakfast."
    - "Coach", "The Coach needs a quick answer.", "Your message is saved. Open Mivu for the Coach's reply."
    - "%@ logged", "%@ is ready to review", "Tap to review", "Couldn't recognize your meal"
    - the five `TellCoachOutcome.dialog` strings
    - "Tell Coach", "Snap It" (expected to stay Latin: assert it equals "Snap It"), "Open Coach"
  - `hebrewShortcutPhrasesNameTheApp`: decode `AppShortcuts.xcstrings` from the bundle source (read the file path from `#filePath`). Every `he` phrase contains `${applicationName}`, and no two shortcuts share a phrase.
- [ ] **Step 2: Run** the three suites. Expected: `morningReminderRefreshesWhenEnabled` fails because `refresh` doesn't exist. The Hebrew key tests should pass. If one fails, fix the catalog and add the key to the review page.
- [ ] **Step 3: Implement** `refresh()` and call it once per app activation, next to the existing launch work.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `fix(notifications): reschedule the morning reminder in the current language`.

### Task 3: Widgets, Control, Live Activity and Siri, captured in Hebrew

**Files:**
- Modify only what the captures show is wrong. Likely places: `ios/MivuWidgets/CaloriesWidget.swift` and `ios/MivuWidgets/DayProgressLiveActivity.swift`, for `minimumScaleFactor`, `fixedSize` or alignment.
- Proof: `docs/verification/2026-11-15-languages-step3.md` and captures

- [ ] **Step 1: Set my own simulators' system language to Hebrew.** The widget extension follows the system language, not `-AppleLanguages`. Targets: "Mivu languages iPhone 18 Pro (Claude)" and "Mivu languages Duo (Claude)". Run `xcrun simctl spawn <id> defaults write "Apple Global Domain" AppleLanguages -array he`, set `AppleLocale he_IL`, then reboot the simulator. Install a Debug build.
- [ ] **Step 2: Capture each surface through the device tools.**
  - Home Screen widgets: small and medium.
  - Lock Screen: circular and rectangular.
  - The Log Food control in Control Center.
  - The Live Activity on the Lock Screen and in the Dynamic Island, compact and expanded. Use the sweep fixture with a target set, then turn on "Dynamic Island" in Settings.
  - The Duo, closed and open.
  - Capture each at the default text size and at the largest.
- [ ] **Step 3: Check each capture** for English left over, text cut off, bars that should fill from the right, and Pip flipped. Fix with the smallest layout change and capture again. Each fix needs an English capture of the same surface, compared with `main`, to show English didn't change.
- [ ] **Step 4: Siri.** In the Shortcuts app on the Hebrew simulator, confirm that the three Mivu shortcuts show Hebrew titles. Run "Tell Coach" from Shortcuts and capture the Hebrew dialog. Live spoken Siri in Hebrew is a physical-device check (Task 7).
- [ ] **Step 5: Put the simulators back** to `en` and reboot them, so later English runs aren't affected.
- [ ] **Step 6: Commit** any fixes as `fix(widgets): …`, with the captures listed in the record.

### Task 4: Settings Language row

**Files:**
- Modify: `ios/Mivu/Diary/SettingsView.swift:196-199`
- Modify: `ios/Mivu/Localizable.xcstrings`
- Test: `ios/MivuUITests/LanguageSweepUITests.swift`

**Interfaces:**
- Produces: `static var shipsSeveralLanguages: Bool { Bundle.main.localizations.filter { $0 != "Base" }.count > 1 }`. Release builds strip hidden languages, so this stays false until Task 6 without any extra flag.

- [ ] **Step 1: Write the failing UI test.** `testLanguageRowOpensSystemSettings` runs in hebrew mode, where the Debug build ships two languages. Open Settings → Diary preferences. The button `languageSettings` exists, is at least 44 points tall, and its label is the Hebrew for "Language". In english mode the test skips. The English text "English is supported for this version…" is gone in hebrew mode.
- [ ] **Step 2: Run** it. Expected: FAIL (no `languageSettings`).
- [ ] **Step 3: Implement.**
  - If `shipsSeveralLanguages` is false, the section stays exactly as it is.
  - Otherwise the section shows the same `LabeledContent` as a button that opens `UIApplication.openSettingsURLString`. That URL opens Mivu's page in iOS Settings, which has the system Language picker.
  - The footnote becomes "Change the language Mivu uses in iOS Settings." with a translator comment, plus Hebrew from the glossary. Add the Hebrew to the review page.
  - Identifier: `languageSettings`.
- [ ] **Step 4: Run** the test and `testTextIsHebrew`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(settings): language row opens the system language page`.

### Task 5: Hebrew App Store listing and screenshots

**Files:**
- Create: `docs/app-store/listing.he.md`
- Create: `docs/app-store/screenshots/he/01-coach.png` … `05-diary.png`
- Create: `scripts/app-store/frame.swift` (AppKit, no dependencies; reusable for the next language)
- Modify: `docs/app-store/listing.md` (link to the Hebrew file; note that the 6.9-inch set is per language)

- [ ] **Step 1: Translate `listing.md`.** Fields:
  - Name (30), subtitle (30), promotional text (170), keywords (100), description (4000), What's New.
  - Neutral voice; "Mivu" in Latin letters; Pip is "פיפ".
  - Keywords are words Israelis search for ("ספירת קלוריות", "יומן אוכל", "חלבון"…), not a word-for-word translation.
  - Count every limit with `python3 -c 'print(len(open(...).read()))'`, field by field, and write the counts in the file.
  - First ask the owner whether the live 1.2.0 listing differs from `listing.md`; translate the live text if it does.
- [ ] **Step 2: Capture the five screens in Hebrew** on a 6.9-inch simulator of my own (create "Mivu store 6.9 (Claude)" if none exists).
  - Same method as the English set: the simulator in Hebrew, a real ChatGPT connection, and meals, targets and weights entered through Coach in Hebrew. The emulator sign-in consent is authorized for test sign-ins.
  - Status bar 9:41.
  - This run is also step 2's missing live check that Coach replies in Hebrew. Record the replies' language in the record.
  - No real personal data: invented meals only.
- [ ] **Step 3: Write `frame.swift`.**
  - Usage: `swift scripts/app-store/frame.swift <in.png> <out.png> "<caption>" [--rtl]`.
  - Output: 1320 × 2868, brand teal background (`0x006D75`), a bold white caption centered above the screenshot, with right-to-left writing direction when `--rtl` is passed.
  - Measure the English set's layout (caption size, margins, corner radius) from `docs/app-store/screenshots/01-coach.png` so both sets match.
  - Self-check: running it on an English raw capture with the English caption gives an image whose caption box and screenshot box sit within 4 pixels of the existing PNG. Write down the numbers.
- [ ] **Step 4: Frame the five** with Hebrew captions from `listing.he.md`. Add the captions to the owner's review page.
- [ ] **Step 5: Owner review.** Put the listing text, captions and screenshots on the existing review page (`https://claude.ai/artifact/UG2zLJEM9zNMF8esUSBuW2`, a new "Store" area). Apply the owner's choices.
- [ ] **Step 6: Commit** `docs(app-store): Hebrew listing and screenshots`.

### Task 6: Switch Hebrew on

Only after Tasks 1–5 are merged, or green on this branch, and the owner has reviewed the new strings and the store page.

**Files:**
- Modify: `ios/Mivu.xcodeproj/project.pbxproj` (`MIVU_HIDDEN_LANGUAGES = "";` in project Debug and Release; keep the strip phases for the next language)
- Modify: `AGENTS.md:24-27`, `docs/development/adding-a-language.md`, `docs/parity.md`

- [ ] **Step 1: Change the setting.** Run `python3 scripts/ci/languages.py check` and `scripts/ci/test_languages.py`. Expected: exit 0 and 23/23. `hidden_errors` returns `[]` for an empty set.
- [ ] **Step 2: Release build for the simulator.** `he.lproj` must be in both `Mivu.app` and `MivuWidgets.appex`. Launch it with `-AppleLanguages (he)`: Today shows Hebrew, and the Settings Language row appears. Launch in English: everything is unchanged except the Language row.
- [ ] **Step 3: Run the sweeps on the Release-equivalent source:** english, rtl, double and hebrew, iPhone and Duo. Then run `CompanionUITests`, `LiveActivityUITests` and the Task 1–2 unit suites. Expected: as in the step 2 record, plus the new tests.
- [ ] **Step 4: Docs.**
  - `AGENTS.md`: Mivu ships English and Hebrew.
  - `adding-a-language.md`: the switch-on step is "remove it from `MIVU_HIDDEN_LANGUAGES`".
  - `parity.md`: the `languages` row says Hebrew is shipped; add rows for Hebrew widgets and Live Activity, Siri, notifications and reports, each with Android `pending`.
- [ ] **Step 5: Commit** `feat(languages): ship Hebrew`.

### Task 7: Record, device checks and PR

- [ ] **Step 1: Write `docs/verification/2026-11-15-languages-step3.md`.** Include: the SHA, the environment, every result count, the captures, the PDF and CSV pages, the store set, the live Coach check, and what was blocked.
- [ ] **Step 2: Physical Duo checks, only if the owner agrees to another install.**
  - Spoken Siri in Hebrew ("לשאול את פיפ ב-Mivu").
  - VoiceOver on Today and Coach.
  - Hebrew dictation in the Coach mic.
  - The owner does these, or they are listed as blocked.
- [ ] **Step 3: Ponytail Review** of the branch. Fix blocking findings.
- [ ] **Step 4: Push and open the PR** `feat(languages): Hebrew widgets, Siri, reports and store listing, and ship Hebrew`. Note in the PR:
  - the English change (the Language row);
  - that users get Hebrew with the next App Store version, which the owner packages and submits, with the Hebrew listing uploaded by the owner;
  - the blocked items.

## Not in this plan

- **Receipt cards in the turn's language** (spec step 2; skipped in step 2). Cards follow the app language. Doing it needs every card string looked up through a per-language bundle. Proposal: amend the spec to "cards follow the app language" unless the owner wants it.
- Android, region units, translating saved foods.
- Uploading to App Store Connect and submitting a version; both are the owner's.
