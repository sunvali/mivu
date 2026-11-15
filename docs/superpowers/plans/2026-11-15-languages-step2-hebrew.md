# Languages step 2: Hebrew, Coach languages and voice — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hebrew is fully translated and reviewed, Coach replies in the language of each message, receipts follow the turn's language, and the mic can listen in another language, while Hebrew stays hidden from users (Release builds) until step 3 ends.

**Architecture:** The Hebrew translation goes into the four catalogs and `he` joins `knownRegions`. A Release-only build phase strips any language listed in `MIVU_HIDDEN_LANGUAGES`, so Debug builds, tests and captures run in Hebrew while shipped builds don't. Coach gets its reply-language rules in the prompt. A small `CoachTurnLanguage` resolves a turn's locale from its text with `NLLanguageRecognizer`, and receipts render under `.environment(\.locale, …)`. Voice input takes a locale chosen from the app language or the keyboards that speech supports.

**Tech Stack:** Swift 6, SwiftUI, iOS 26+, String Catalogs, NaturalLanguage (`NLLanguageRecognizer`), Speech (`SpeechTranscriber` / `DictationTranscriber`), XCTest / Swift Testing, Python 3 (`scripts/ci/languages.py`).

**Spec:** `docs/superpowers/specs/2026-11-14-languages-design.md` ("Step 2" plus the 2026-11-15 decisions). Step 1 record: `docs/verification/2026-11-14-languages-step1.md`. Recipe: `docs/development/adding-a-language.md`.

## Global Constraints

- Base: `main` at `732dfe6d` (step 1 merged). iOS 26 minimum, Swift 6.
- "Stored and model-facing values never localize. Dates, numbers, record types, tool names, tool arguments and prompts keep their fixed formats."
- "Digits are 0–9 in every language for now, including in Pip's replies."
- "Dates shown to people use the Gregorian calendar in the person's language." The week start is unchanged.
- Hebrew: "gender-neutral wording everywhere, on screens and from Pip". "Mivu" stays in Latin letters; the fox is "פיפ"; the Coach tab is "פיפ".
- Charts over time keep time running left to right in every language. Pip's artwork never flips.
- Mixed text aligns by the script with more letters; ties go right to left.
- "Hebrew is switched on for users at the end of step 3." Release builds must not contain `he.lproj` until then.
- "English wording does not change", except plural fixes listed in the PR. English tests stay pinned to `en`/`US` in `Mivu.xctestplan`.
- Owner reviews every Hebrew string on one page before merge. Never accept terms or sign in for the owner; live checks use `request_secret`.
- Commits use Conventional Commit titles and never mention AI tools. Run targeted tests only. Use only simulators named "… (Claude)" that you created; never the owner's phones. Record the exact tested SHA.

## Review Focus

1. A message with no letters (a photo alone, "200", an emoji) gets a reply and receipts in the app language, with no crash → tests in Task 2 (`noLettersHasNoDirection`) and Task 6 (`textWithoutLanguageUsesTheAppLanguage`).
2. A Hebrew message on an English phone where the model writes "72,5" or "72.5" saves weight 72.5 and the reply passes the check → Task 4 (`commaDecimalReadsAsOneNumber`) and Task 10 (`hebrewDecimalWeightSavesTheSameRecord`).
3. A Release build on a Hebrew phone still shows English → Task 7 (Release bundle check) and Task 10 (Debug shows Hebrew).
4. A message in a language Mivu doesn't ship (Arabic) still gets its reply, and the receipt labels use the app language → Task 6 (`unshippedLanguageUsesTheAppLanguage`).
5. The mic never offers a language speech can't transcribe, and still works when the app language isn't supported (the simulator) → Task 9 (`unsupportedKeyboardsAreNotOffered`, `appLanguageComesFirstWhenSupported`).

---

### Task 1: Catalog lint: unknown languages, translator comments

**Files:**
- Modify: `scripts/ci/languages.py` (`PLURAL_FORMS` lookup, `errors`)
- Modify: `scripts/ci/test_languages.py`
- Modify: `ios/Mivu/Localizable.xcstrings`, `ios/MivuWidgets/Localizable.xcstrings` (comments, `shouldTranslate`)
- Modify: `docs/development/adding-a-language.md`

**Interfaces:**
- Produces: `languages.py check` fails when (a) a bundled language is missing from `PLURAL_FORMS`: "add CLDR plural forms for '<lang>' to PLURAL_FORMS"; (b) a translatable key whose text, with placeholders removed, has at most 2 words has no `comment`: "'<key>' needs a translator comment"; (c) a key with no letters isn't marked `"shouldTranslate": false`: "'<key>' has no words; mark it shouldTranslate false".

- [ ] **Step 1: Write failing tests** in `test_languages.py`:
  - `test_language_without_plural_table_fails`: `errors(catalog(**{'%lld meals': {'localizations': {'en': PLURAL, 'de': PLURAL}}}), {'en','de'})` includes "add CLDR plural forms for 'de'".
  - `test_short_key_needs_a_comment`: `Open={}` → an error naming `'Open'`; `Open={'comment': 'Day status: the day is still open'}` → no error.
  - `test_key_without_words_must_not_translate`: `'%@ · %@'={}` → error; with `'shouldTranslate': False` → none.
  - Update `test_clean_catalogs_pass`: give `Account` a comment.
- [ ] **Step 2: Run** `python3 -m unittest scripts/ci/test_languages.py`. Expected: the 3 new tests FAIL.
- [ ] **Step 3: Implement** the three rules in `errors`. Words are counted with `re.sub(PLACEHOLDER, '', key).split()`; "has letters" means any `str.isalpha()` character. Also add `'de': {'one','other'}`, `'en': {'one','other'}`, `'ja': {'other'}`, `'zh': {'other'}`, `'ko': {'other'}` to `PLURAL_FORMS`.
- [ ] **Step 4: Fill the catalogs** so `python3 scripts/ci/languages.py check` passes. Edit the JSON by script and keep Xcode's formatting (`json.dumps(indent=2, separators=(',', ' : '), ensure_ascii=False)` round-trips the file exactly). About 470 short keys need a one-line comment saying where the text appears and what it means (for example `"Open"` → "Diary day status: the day is still open, not a button"). Find each key's use with `rg -F '"<key>"' ios/Mivu`. Mark letterless keys `shouldTranslate: false`.
- [ ] **Step 5: Run** `python3 -m unittest discover -s scripts/ci -p 'test_*.py'` and `python3 scripts/ci/languages.py check`. Expected: OK, exit 0.
- [ ] **Step 6: Document** the comment rule and the `PLURAL_FORMS` row in `adding-a-language.md` under "What a language pull request contains".
- [ ] **Step 7: Commit** `chore(languages): require translator comments and known plural forms`.

### Task 2: Mixed text aligns by the script with more letters

**Files:**
- Modify: `ios/Mivu/Design/TextDirection.swift` (`TextDirection.of`)
- Test: `ios/MivuTests/TextDirectionTests.swift`

**Interfaces:**
- Produces: `TextDirection.of(_ text: String) -> LayoutDirection?`. The signature is unchanged; the rule changes. Count letters (`properties.isAlphabetic`) in the right-to-left ranges against all other letters. More right-to-left letters, or a tie with at least one letter, gives `.rightToLeft`; more others gives `.leftToRight`; no letters gives `nil`.

- [ ] **Step 1: Write failing tests:**
  - `#expect(TextDirection.of("KitKat שוקולד") == .rightToLeft)` (tie)
  - `#expect(TextDirection.of("200 g סלט") == .rightToLeft)`
  - `#expect(TextDirection.of("Pizza with פיצה") == .leftToRight)`
  - `#expect(TextDirection.of("قهوة مع حليب") == .rightToLeft)`
  - `noLettersHasNoDirection`: `#expect(TextDirection.of("200 🍕") == nil)`
  - Update any existing case that asserted the first-letter rule ("200 g סלט" was left to right).
- [ ] **Step 2: Run** `xcodebuild test … -testPlan Mivu -only-testing:"MivuTests/TextDirectionTests"`. Expected: FAIL on the tie and the "200 g" cases.
- [ ] **Step 3: Implement** the counting rule in `TextDirection.of`, keeping the existing ranges.
- [ ] **Step 4: Run** the same tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat(languages): align mixed text by its main script`.

### Task 3: Gregorian everywhere, unit words, missing plurals

**Files:**
- Modify: `ios/Mivu/Coach/CoachReplyLines.swift` (`dayLabel`, `shortDate`)
- Modify: `ios/Mivu/Diary/DiaryReportPDF.swift` (`dayTitle`)
- Modify: `ios/Mivu/Coach/CoachView.swift` (chat timestamp near line 414), `ios/Mivu/Coach/CoachHistoryView.swift:171` (`captureLabel`)
- Modify: `ios/Mivu/Progress/ProgressView.swift:350,440` (weight unit)
- Modify: `ios/Mivu/Localizable.xcstrings`
- Test: `ios/MivuTests/LanguageTextTests.swift`

**Interfaces:**
- Produces: every `Date.FormatStyle` built for people in these files passes `calendar: Calendar(identifier: .gregorian)`. `WeightEntry`'s unit shows through `String(localized: "kg")` / `String(localized: "lb")`; the stored value stays `"kg"`/`"lb"`.

- [ ] **Step 1: Write failing tests:**
  - `coachDatesStayGregorian`: `CoachReplyLines.shortDate("2026-10-19", locale: Locale(identifier: "en_US@calendar=buddhist")) == "Oct 19"`, and `dayLabel("2025-10-19", today: "2026-10-19", locale: Locale(identifier: "en_US@calendar=hebrew"))` contains "2025".
  - `countsUsePluralForms`: `String(localized: "Down \("1.0") kg in \(1) days") == "Down 1.0 kg in 1 day"`, and `String(localized: "Added \(1) photos") == "Added 1 photo"` (use the exact keys that exist in code: `ProgressCards.swift:69`, `DiaryDatabaseQueries.swift:432`, `ProgressView.swift:428,432`, `CoachReplyLines.swift:15`).
- [ ] **Step 2: Run** `-only-testing:"MivuTests/LanguageTextTests"`. Expected: FAIL.
- [ ] **Step 3: Implement.** Pass the Gregorian calendar in the four format styles. Add `one`/`other` plural variations (and a `%#@…@` substitution where the key has two counts) to the keys from Step 1, by script in the house JSON format. Map the weight unit as in Interfaces. These English changes are plural fixes; list them in the PR.
- [ ] **Step 4: Run** the tests and `python3 scripts/ci/languages.py check`. Expected: PASS, exit 0.
- [ ] **Step 5: Commit** `fix(languages): Gregorian dates in Coach and reports, plural counts, unit words`.

### Task 4: Reply check reads comma decimals and the `~` hedge in any language

**Files:**
- Modify: `ios/Mivu/Coach/CoachReplyCheck.swift` (`numbers(in:)`, `passes`)
- Test: `ios/MivuTests/CoachReplyCheckTests.swift`

**Interfaces:**
- Produces: `numbers(in:)` reads `d+,d{1,2}` (a comma followed by 1 or 2 digits, not part of a longer number) as one decimal, and still reads `1,234` as a thousand. Thin and no-break spaces (U+202F, U+00A0) between digit groups count as grouping. In `passes`, the `generalFacts` hedge accepts a sentence whose number is preceded by `~` in any script, as today. The English word list stays, marked `shortcut:`.

- [ ] **Step 1: Write failing tests:**
  - `commaDecimalReadsAsOneNumber`: `CoachReplyCheck.numbers(in: "73,5 кг") == [73.5]`; `numbers(in: "2,25") == [2.25]`; `numbers(in: "1,240 kcal") == [1240]`; `numbers(in: "1 240") == [1240]` (with U+202F).
  - `hebrewHedgedGeneralFactPasses`: `passes("בתפוח יש ~95 קק״ל.", allowed: [], receipts: [], generalFacts: true) == false` (no review-only receipt) and `== true` with one awaiting-review receipt fixture, as in the existing English `generalFacts` tests.
- [ ] **Step 2: Run** `-only-testing:"MivuTests/CoachReplyCheckTests"`. Expected: FAIL on the comma cases.
- [ ] **Step 3: Implement** the comma-decimal and space-grouping reading in the token regex/normaliser. Unreadable tokens still return NaN (fail closed).
- [ ] **Step 4: Run** the tests. Expected: PASS.
- [ ] **Step 5: Commit** `fix(coach): read comma decimals and grouped digits in replies`.

### Task 5: Coach replies in the language of the message

**Files:**
- Modify: `ios/Mivu/Coach/CoachEngine.swift` (`stableRules`; the dynamic developer message at line 42)
- Test: `ios/MivuTests/CoachEngineTests.swift`

**Interfaces:**
- Produces: `stableRules` gains this exact text, before "Reply to the user in at most two short sentences":
  "Reply in the language of the person's latest message. If it has no clear language (only a photo, numbers or units), reply in the app language given in the context. Write digits as 0–9, use a dot for decimals and no thousands separators except commas in groups of three. In languages with grammatical gender, never assume the person's gender and speak as Pip without gendered forms: prefer plural, infinitive or impersonal wording. Name foods in the language the person used. Outside English, mark a typical food value with ~ right before the number."
  The dynamic message gains `"The app language is \(appLanguageName). "`, where `appLanguageName = Locale(identifier: "en").localizedString(forLanguageCode: Bundle.main.preferredLocalizations.first ?? "en") ?? "English"`.

- [ ] **Step 1: Write failing tests:**
  - `promptAsksForTheMessageLanguage`: run a fixture turn, read the first input of `replies.inputs[0]`, and expect it to contain "Reply in the language of the person's latest message" and "never assume the person's gender".
  - `promptNamesTheAppLanguage`: the second developer message contains "The app language is English." (test plan pins `en`).
- [ ] **Step 2: Run** `-only-testing:"MivuTests/CoachEngineTests"`. Expected: the 2 new tests FAIL.
- [ ] **Step 3: Implement** as in Interfaces.
- [ ] **Step 4: Run** the suite. Expected: PASS. The `tools.json` fixture test was already failing on `main`; note it if it still fails.
- [ ] **Step 5: Commit** `feat(coach): reply in the language of each message`.

### Task 6: Receipts follow the turn's language

**Files:**
- Create: `ios/Mivu/Coach/CoachTurnLanguage.swift`
- Modify: `ios/Mivu/Coach/CoachView.swift` (the receipt `ForEach` blocks near line 777)
- Test: `ios/MivuTests/CoachTurnLanguageTests.swift`

**Interfaces:**
- Produces: `enum CoachTurnLanguage { static func locale(for text: String, shipped: [String] = Bundle.main.localizations, app: Locale = .current) -> Locale }`. It uses `NLLanguageRecognizer.dominantLanguage(for:)`. The result is `Locale(identifier: code)` when the recognised code is in `shipped` (ignore `"Base"`), otherwise `app`. Text with no letters returns `app`. Nothing is stored.
- In `CoachView`, both receipt `ForEach` bodies get `.environment(\.locale, CoachTurnLanguage.locale(for: turn.text))`. Buttons, tabs and the composer are untouched.

- [ ] **Step 1: Write failing tests:**
  - `shippedLanguageIsUsed`: `locale(for: "אכלתי חביתה משתי ביצים", shipped: ["en","he"], app: Locale(identifier: "en_US")).language.languageCode == "he"`.
  - `unshippedLanguageUsesTheAppLanguage`: Arabic text with `shipped: ["en","he"]` returns the app locale.
  - `textWithoutLanguageUsesTheAppLanguage`: `"200"` and `""` return the app locale.
- [ ] **Step 2: Run** `-only-testing:"MivuTests/CoachTurnLanguageTests"`. Expected: FAIL (type missing).
- [ ] **Step 3: Implement** `CoachTurnLanguage` and the two environment modifiers.
- [ ] **Step 4: Run** the tests plus `CoachReceiptPresentationTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(coach): show receipt labels in the turn's language`.

### Task 7: Keep hidden languages out of Release builds

**Files:**
- Modify: `ios/Mivu.xcodeproj/project.pbxproj`: project build setting `MIVU_HIDDEN_LANGUAGES = he`; a "Strip hidden languages" Run Script phase, last in the `Mivu` and `MivuWidgets` targets
- Modify: `scripts/ci/languages.py`, `scripts/ci/test_languages.py`
- Modify: `docs/development/adding-a-language.md` (a "Shipping a hidden language" section)

**Interfaces:**
- Produces: in the `Release` configuration the phase runs `for l in $MIVU_HIDDEN_LANGUAGES; do rm -rf "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/$l.lproj"; done`. Debug does nothing. The phase declares its output path so script sandboxing allows it. `languages.py check` fails unless every language in `MIVU_HIDDEN_LANGUAGES` is in `knownRegions` and both targets contain the phase: "hidden language '<l>' is not stripped from <target>".
- Switching a language on for users (step 3) means removing it from `MIVU_HIDDEN_LANGUAGES`.

- [ ] **Step 1: Write failing tests:** `test_hidden_language_needs_the_strip_phase` feeds `hidden_errors(pbxproj_text)` a project string with `MIVU_HIDDEN_LANGUAGES = he` and no phase, and expects 2 errors (Mivu, MivuWidgets). Then add the phase text and expect none.
- [ ] **Step 2: Run** the Python tests. Expected: FAIL (`hidden_errors` missing).
- [ ] **Step 3: Implement** `hidden_errors(pbxproj: str) -> list[str]`, call it from `check`, and add the setting and the phases to the project.
- [ ] **Step 4: Verify the bundle.** Build `-configuration Release` for the simulator, then run `find …/Release-iphonesimulator/Mivu.app -name 'he.lproj'`. Expected: no output (it can't produce any until Task 8 adds `he`; repeat this check after Task 8). Build Debug. Expected: the build succeeds.
- [ ] **Step 5: Commit** `build(languages): strip hidden languages from Release builds`.

### Task 8: Hebrew translation, glossary and owner review

**Files:**
- Create: `docs/languages/he.md` (glossary, written before the draft)
- Modify: the four catalogs (`he` localizations); `ios/Mivu.xcodeproj/project.pbxproj` (`knownRegions` adds `he`)
- Create: `scripts/languages/review_page.py` (owner review page)
- Delete: `docs/languages/he-legacy.json` once reused

**Interfaces:**
- Consumes: Task 1 comments; Task 7 hiding.
- Produces: `python3 scripts/languages/review_page.py he > <scratchpad>/he-review.html` writes one HTML table: key, English, Hebrew, comment, and where it is used (`file:line` from `rg -n -F`). The page is published as a private Artifact for the owner.

- [ ] **Step 1: Write `he.md`** with these sections:
  - **Voice.** Gender-neutral throughout:
    - buttons use nouns or infinitives ("שמירה", "ביטול");
    - instructions use the plural imperative or impersonal forms ("אפשר לנסות שוב");
    - Pip speaks with past tense, impersonal or plural forms ("נרשם", "הכול מוכן") and never with "אתה/את".
  - **Names.** "Mivu" in Latin letters; "פיפ".
  - **Fixed terms:**
    - קק״ל next to numbers, קלוריות in prose;
    - גרם (never ג׳);
    - Coach tab = פיפ;
    - Cancel = ביטול, Undo = ביטול פעולה;
    - Log meal = הוספת ארוחה;
    - app = אפליקציה;
    - waking day = היום שלך (owner to confirm);
    - ASCII hyphen before Latin words ("ל-ChatGPT"), not the maqaf.
  - **Plurals.** Use one, two and other; digits stay 0–9.
  - **Weak legacy terms not to reuse:** יום ערות, יישום, נערך על ידיכם, סכומים מתועדים.
- [ ] **Step 2: Draft** `he` for every key in all four catalogs. Reuse `he-legacy.json` where it still fits the glossary. Every key with a plural variation gets `one`, `two` and `other`. Add `he` to `knownRegions`.
- [ ] **Step 3: Run** `python3 scripts/ci/languages.py check`. Expected: exit 0.
- [ ] **Step 4: Repeat the Task 7 bundle check:**
  - Release: `find … -name he.lproj` shows nothing.
  - Debug: `Mivu.app/he.lproj` exists.
- [ ] **Step 5: Owner review.**
  - Generate the review page, publish it, and send the owner the link.
  - Apply every correction the owner gives.
  - Ask the owner to confirm the "waking day" term.
- [ ] **Step 6: Commit** `feat(languages): Hebrew translation (hidden until step 3)`. Delete `he-legacy.json` in the same commit.

### Task 9: Mic listens in the app language, with a quick switch

**Files:**
- Create: `ios/Mivu/Coach/CoachVoiceLanguages.swift`
- Modify: `ios/Mivu/Coach/CoachVoiceInput.swift:48` (drop the fixed `en-US`; take a `Locale`)
- Modify: the mic button in `ios/Mivu/Coach/CoachView.swift`: a context menu (long press) that lists the options
- Test: `ios/MivuTests/CoachVoiceLanguagesTests.swift`

**Interfaces:**
- Produces: `enum CoachVoiceLanguages { static func options(app: Locale, keyboards: [String], supported: (Locale) -> Bool) -> [Locale] }`. The app locale comes first when supported. Keyboard languages follow (`UITextInputMode.activeInputModes.compactMap(\.primaryLanguage)`), de-duplicated by language code and kept only when `supported` is true. If nothing is supported, the result is `[Locale(identifier: "en-US")]`.
- `CoachVoiceInput.start(locale: Locale)` uses `SpeechTranscriber.supportedLocale(equivalentTo: locale)`, then the `DictationTranscriber` fallback, as today. The chosen locale lasts for the session only (`@State`); each launch starts in the app language.
- The menu shows each option as `option.localizedString(forLanguageCode:)` in its own language. It has an accessibility label "Listening language, <name>".

- [ ] **Step 1: Write failing tests:**
  - `appLanguageComesFirstWhenSupported`: `options(app: he_IL, keyboards: ["en-US","he"], supported: { _ in true }).map(\.language.languageCode) == ["he","en"]`.
  - `unsupportedKeyboardsAreNotOffered`: with `supported` false for `"ar"`, the list has no `"ar"`.
  - `nothingSupportedFallsBackToEnglish`: with `supported` always false, the result is `["en-US"]`.
- [ ] **Step 2: Run** `-only-testing:"MivuTests/CoachVoiceLanguagesTests"`. Expected: FAIL.
- [ ] **Step 3: Implement** `options`, the locale parameter and the menu. `supported` at runtime is `{ await SpeechTranscriber.supportedLocale(equivalentTo: $0) != nil || await DictationTranscriber.supportedLocale(equivalentTo: $0) != nil }`, computed once when the menu opens.
- [ ] **Step 4: Run** the tests plus `CompanionUITests/testLivingIdleAndQuietTypingKeepCaptureResponsive`, so the mic button still works. Expected: PASS.
- [ ] **Step 5: Commit** `feat(coach): pick the listening language for voice input`.

### Task 10: Hebrew sweep and journeys

**Files:**
- Modify: `ios/MivuUITests/LanguageSweepUITests.swift` (new `hebrew` mode; replace `testHebrewPhoneGetsEnglish`)
- Modify: `ios/MivuTests/CoachEngineTests.swift` (journey twins)
- Modify: `docs/verification/languages/README.md`

**Interfaces:**
- Produces:
  - `SWEEP_MODE=hebrew` launches with `-AppleLanguages (he) -AppleLocale he_IL`.
  - `testTextIsHebrew` visits all 12 screens and fails on any visible label with a Latin letter, except fixture data and the allowlist `["Mivu", "ChatGPT", "OpenAI", "Apple", "USDA"]`.
  - `testHebrewPhoneGetsHebrew` (hebrew mode) replaces `testHebrewPhoneGetsEnglish`: the tabs read "היום", "יומן", "התקדמות", "פיפ", and the Today tab sits to the right of the פיפ tab.

- [ ] **Step 1: Write the UI tests** above. Run `SWEEP_MODE=hebrew -only-testing:MivuUITests/LanguageSweepUITests`. Expected: PASS after Task 8. Any English label found is a missing translation: fix the catalog, not the allowlist.
- [ ] **Step 2: Write the journey twins** in `CoachEngineTests`. Each Hebrew turn and its English twin must save identical records (same name text as written, quantities, numbers):
  - `hebrewMealOnEnglishPhoneSavesTheSameRecord`
  - `hebrewDecimalWeightSavesTheSameRecord` (model says "72,5")
  - `hebrewCorrectionMatchesEnglish`
  - `hebrewUndoMatchesEnglish`
  - `spanishMealSavesTheSameRecord` (a second language, so nothing is Hebrew-only)
  Each reply includes `<saved/>` and passes.
- [ ] **Step 3: Run** `-only-testing:"MivuTests/CoachEngineTests"`. Expected: PASS.
- [ ] **Step 4: Capture** `english`, `rtl` and `hebrew` on the iPhone 18 Pro simulator, and the Duo simulator in closed, open-upright, table and book poses (device tool `fold` + `orientation landscape-left`). Save contact sheets in `docs/verification/languages/step2/`. Check VoiceOver labels via the accessibility snapshot in Hebrew.
- [ ] **Step 5: Commit** `test(languages): Hebrew sweep and cross-language journeys`.

### Task 11: Live model check, record and PR

**Files:**
- Create: `docs/verification/2026-11-15-languages-step2.md`
- Modify: `docs/parity.md` (`languages` row: step 2 done on iOS, Android pending)

- [ ] **Step 1: Sign in.** Ask the owner to sign in to ChatGPT on your Duo simulator with `request_secret` (email, then password, then any code), one value per card. Never put credentials in chat or files.
- [ ] **Step 2: Send these live messages** on an English-language simulator (Debug build) and record the reply language, whether the save marker held (a receipt or an error, never a false "saved"), and any gendered Hebrew:
  1. "אכלתי חביתה משתי ביצים וסלט"
  2. "I had a banana"
  3. "כמה קלוריות יש בתפוח?"
  4. "אני חושב לאכול פיצה"
  5. "שקלתי הבוקר 72.5"
  6. "Comí dos huevos"
  Then switch the simulator to Hebrew and send message 2 again.
- [ ] **Step 3: Write the record.** Include the SHA, the environment, every result, the captures, and what was blocked (Siri, real-device VoiceOver).
- [ ] **Step 4: Run Ponytail Review.** Fix any blocking findings, then run the targeted suites again:
  - `LanguageSweepUITests` in english, rtl, double and hebrew modes;
  - `CoachReplyUITests`, `CompanionUITests`;
  - the changed unit suites.
- [ ] **Step 5: Push and open the PR** `feat(languages): Hebrew translation and Coach in the message's language`. Note in it that Hebrew stays hidden from Release builds until step 3 and list the plural fixes.
