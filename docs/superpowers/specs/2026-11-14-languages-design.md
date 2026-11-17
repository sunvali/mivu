# Many languages, starting with Hebrew: design

Date: 2026-11-14. Status: draft for owner approval. Platform: iOS. Baseline:
`main` at `72e05279`.

## Intent

The owner wants Mivu to be ready for many languages, added one at a time in
small pull requests. Hebrew is first, so right-to-left layout has to work, but
nothing may be built for Hebrew alone: Arabic, Russian, Spanish and a broad set
of others (French, German, Portuguese and more) are expected to follow soon.

The owner's hard condition: this must not introduce bugs. English users must
notice nothing, and saved diaries must stay exactly as compatible as today.

## Where the app is today

- `MivuApp.swift:9` and every sheet (Settings, meal detail, composer, manual
  nutrition, Progress editors, Coach) force `Locale("en")` and left-to-right.
- About 600 pieces of on-screen text are written in code. The string catalog
  holds 229 keys with 228 Hebrew translations left from the first MVP; most
  screens built since are not in it.
- Notifications, Siri replies, widgets, the Live Activity and reports use
  English text from code. Voice input is pinned to `en-US`
  (`CoachVoiceInput.swift:48`).
- Coach logic has English-word checks: `CoachReplyCheck.passes` looks for
  "logged"/"saved", and `CoachEngine.swift` (near lines 66 and 143) matches
  lowercased English words. In another language these silently stop applying.
- Stored and model-facing values (dates as `yyyy-MM-dd`, numbers, tool names,
  prompts) use fixed `en_US_POSIX` formatting. That is correct and stays.
- `AGENTS.md` currently says the MVP is English-only with the Hebrew selector
  disabled. This design, once approved, replaces that rule; step 1 rewrites it.

## Owner decisions

- **iOS first.** Android is a separate later project that reuses these
  decisions and the approved wording.
- **Language choice:** Mivu follows the phone's language. Mivu's Settings gets a
  **Language** row that opens the iPhone's own per-app language page. No picker
  of our own.
- **Coach is not tied to the app language.** Pip replies in the language of the
  person's message. Someone on an English phone who writes in Hebrew gets a
  Hebrew reply, and the saved-food card for that turn is in Hebrew too. Buttons,
  tabs and the composer stay in the app language. (Approved from mockups.)
- **Voice:** the microphone listens in the app language and has a quick switch
  to another language.
- **In the Hebrew release:** main screens, widgets and Dynamic Island, Siri and
  notifications, PDF and CSV reports, and the App Store listing.
- **Hebrew voice:** gender-neutral wording everywhere, on screens and from Pip.
- **Names:** "Mivu" stays in Latin letters; the fox is "פיפ" in Hebrew text.
- **Translation bar:** for Hebrew, I draft and the owner reviews every string on
  one page before it ships. For languages the owner cannot read, a draft plus an
  independent reviewer agent and an on-screen fit check is enough.
- **Mirroring approved from mockups:** layouts, navigation and the week strip
  mirror; Pip's artwork does not flip; each chat message aligns by its own text.
- **Delivery in three steps** (below), each its own reviewed pull request.
  Because the owner put all four surfaces in the Hebrew release and a language
  ships whole, **Hebrew is switched on for users at the end of step 3**. Steps
  1 and 2 merge with Hebrew still hidden from users. *(My call, following
  from the owner's answers.)*
- **Test on the iPhone Duo** as well as a normal iPhone.
- **Decided 2026-11-15 (after the step 1 reviews):** the Coach tab is "פיפ" in
  Hebrew (gender-neutral, matches "Ask Pip"); charts over time keep time
  running left to right in every language; a mixed-direction text aligns by
  whichever script has more letters (ties go right to left), replacing the
  first-letter rule.
- **Units** (pounds, ounces, feet) are a separate project.

## Goals

1. Any language can be added by a pull request that contains a translation, a
   short glossary, store text and screenshots, and no Swift logic changes.
2. Right-to-left works for any such language, not only Hebrew.
3. Hebrew ships complete: no English left on any surface listed above.
4. English behaviour, saved data, archives and tests are unchanged.

## Non-goals

- Android (tracked in `docs/parity.md` as pending rows).
- Region units and unit conversion.
- Translating foods already saved, or translating the food database.
- A language picker inside Mivu, or a language per profile.
- Any change to the stored diary schema or the portable archive format.

## Anti-goals

- A half-translated screen reaching a user. A language ships whole or not at all.
- Behaviour that depends on English words appearing in a message or a reply.
- A saved number, date or record that reads differently depending on the
  phone's language.
- Layout code that checks for Hebrew by name.

## Rules that hold in every step

- **Stored and model-facing values never localize.** Dates, numbers, record
  types, tool names, tool arguments and prompts keep their fixed formats. Only
  what a person reads is translated and formatted for their language.
- **The old `language` value** on profiles and in archives is preserved as is
  and no longer controls anything on screen. Validation keeps accepting the
  values it accepts today.
- **Digits are 0–9** in every language for now, including in Pip's replies, so
  the reply number check keeps working. *(My call.)*
- **Dates shown to people use the Gregorian calendar** in the person's
  language. *(My call.)*
- **The week keeps starting on the same day it does today** in every language.
  Weekly analytics depend on it; changing it per region is a separate decision.
  *(My call.)*
- **What mirrors:** layout, navigation, swipe directions, back arrows and
  chevrons, the week strip, progress bars that fill. **What does not:** charts
  over time, Pip's artwork, photos, the camera, numbers, the macro colour order
  inside a card follows layout direction like any other row.
- **Mixed text:** any text a person typed, a food name, or a model reply takes
  its direction from its own content (the script with more letters), never
  from the app language.
- **Formatting follows the language on screen.** Dates and numbers people read
  use the same language as the text around them, never a different one. While
  only English ships, a phone set to any other language shows English text
  with English formatting and left-to-right layout. *(My call.)*
- **Chat history is kept as written.** Pip's replies and fixed lines saved in a
  conversation stay in the language they were shown in, like any chat. They
  are not re-translated when the language changes. Receipts and cards are drawn
  from records, so they follow the rules below. *(My call.)*
- **English wording does not change in step 1**, except to fix a visibly wrong
  plural ("1 servings"). Each such fix is listed in its pull request.
  *(My call.)*
- English-only automated tests keep running in English by pinning the language
  at launch. Tests find controls by identifier, not by translated label, where
  a step touches them.

## Step 1: language-ready (no visible change for users)

- Remove every forced English locale and forced left-to-right direction.
- Move all on-screen text into the string catalogs for the app, the widgets
  extension, the Info.plist strings and App Shortcuts. This includes text built
  in code: notification titles and bodies, Siri dialog, receipt lines, Pip's
  lines, error messages, accessibility labels and hints, report headings.
- Counts use proper plural forms ("1 serving", "2 servings"). Sentences are
  whole strings with placeholders, never glued from fragments.
- Numbers, dates, times and percentages people read are formatted for their
  language. Unit words (kcal, g, kg) become translatable strings.
- Fix whatever does not mirror or does not fit, using leading/trailing layout.
- Replace the English-word checks in Coach with signals that work in any
  language (for example the turn's actual saved state rather than the word
  "saved"). The number check must read digits in any script and fail closed
  when it cannot parse one.
- The Hebrew translation is not shown to users in this step: nobody may see the stale
  228 strings next to English. English stays the only user-visible language.
- Write `docs/development/adding-a-language.md`: the recipe, the review bar and
  the verification sweep. Rewrite the English-only rule in `AGENTS.md`.

Proof for step 1: every screen captured in English, in Xcode's right-to-left
pseudolanguage and in the double-length pseudolanguage, on a normal iPhone and
on the iPhone Duo (closed, open upright, open sideways with its splits, book
and table poses), at default and largest text size. English captures match the
baseline.

## Step 2: Hebrew, Coach languages and voice

- First write `docs/languages/he.md` (neutral voice, names, key terms); every
  later language gets the same kind of file before its draft.
- Hebrew translation of every string, reusing the old 228 where still right,
  following `docs/languages/he.md` (neutral voice, names, key terms). The owner
  reviews one page listing each string with its English and where it appears.
- The **Language** row in Settings opens the system per-app language page. It
  appears once Mivu ships more than one language, so at the end of step 3.
- Coach: the model is told to reply in the language of the person's latest
  message, to fall back to the app language when a message has no clear
  language (a photo alone, a number), and to write digits as 0–9. Food names
  are saved as the person wrote them.
- The saved-food card and other receipts for a turn show their labels in the
  app language, whatever language the turn was written in (owner, 2026-11-15).
  Nothing new is stored.
- A message in a language Mivu does not ship yet (Arabic before Arabic exists)
  still gets a reply in that language; its card labels use the app language.
- Fixed fallback lines (shown when a model reply is rejected) use the app
  language.
- Voice: the mic starts in the app language. A small switch on the mic offers
  the phone's enabled keyboard languages that speech recognition supports. If
  a language is not supported for speech, it is not offered. *(My call.)*

Proof for step 2: the same capture sweep in Hebrew on iPhone and Duo;
VoiceOver reads Hebrew labels; targeted tests for a Hebrew message on an
English phone, an English message on a Hebrew phone, a mixed message, a
decimal weight, a correction and an Undo, each compared with its English twin
for identical saved records. One of these journeys is repeated in a second
language (Spanish or Russian text) to show nothing is Hebrew-specific. A live
model check of reply language is recorded separately from fixture tests.

## Step 3: everything around the app

- Widgets, the Log Food control, the Live Activity and Dynamic Island.
- Siri: App Shortcut phrases and spoken confirmations in Hebrew; notifications
  for Coach replies, analyzed meals and the morning reminder.
- PDF report laid out right-to-left with Hebrew headings. CSV gets translated
  column headings; its numbers and dates stay in the fixed machine format so
  spreadsheets read them the same everywhere. *(My call.)*
- App Store listing in Hebrew: name line, subtitle, description, keywords and
  screenshots, prepared in the repository. Uploading them to App Store Connect
  is the owner's action or needs the owner's explicit go-ahead.
- `docs/parity.md` gets rows for these features with Android pending.

Proof for step 3: captures of each surface in Hebrew on iPhone and Duo, a
generated Hebrew PDF and CSV, and named tests for notification and Siri text.

## Adding a language afterwards

One pull request per language containing: the translation in the catalogs, a
glossary file under `docs/languages/`, store text and screenshots, the
language added to the project's list, and the capture sweep on iPhone and Duo.
The draft is checked by an independent reviewer agent for meaning, tone and
fit. Arabic additionally proves the six plural forms and the 0–9 digit rule.

## Verification rules

Follow the repository's evidence rules: exact source SHA, environment, result
counts, blocked gates stated. Run targeted tests only, not the full UI suite.
Fold and unfold with a draft, real-device VoiceOver, and live Siri in Hebrew
are physical-device checks and are reported as blocked if not done.

## Left to the builder

- How step 1 is split into reviewable pull requests (by screen area is fine).
- The mechanism that keeps Hebrew hidden from users until the end of step 3
  while letting tests and captures run in Hebrew.
- The language-independent replacement for each English-word check, with a
  failing test first.
- How a turn's language is detected for receipts.
- The form of the owner's Hebrew review page.
