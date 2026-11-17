# Agent briefs

Fill in `<Language>`, `<code>`, `<market>` (for example "US Hispanic"), `<REPO>`
(absolute repo path) and `<DIR>` (a scratchpad folder for this pass). Add the
owner's fixed choices from the glossary to each brief's hard rules. Rows come from
`python3 scripts/ci/catalog_rows.py export <code> <DIR>/rows.tsv` (columns:
catalog, key, comment, english, current). All output is a JSON array that
`catalog_rows.py apply` takes directly.

## Shared hard rules (paste into every brief)

```
Hard rules:
- Follow the glossary <REPO>/docs/languages/<code>.md exactly, including the owner's fixed choices.
- Keep every placeholder exactly: %@, %lld, %1$@, %%, %#@name@, %arg, ${applicationName}; same kinds and count. Reorder only with positional forms (%2$@ … %1$@). Keep \n and invisible direction marks (U+2066–U+2069, U+200F).
- Only the zero, one and two plural forms may drop the number; every other form keeps it. Rows ending [plural=…] or [sub=…,plural=…] are one form each; write every form the row list has.
- "[phrases]" rows are Siri phrases joined by " | "; each phrase keeps ${applicationName}, and no phrase may repeat another shortcut's.
- Digits 0–9. Short labels (buttons, tabs, widgets, Dynamic Island, Control Center) must not be longer than needed; watch those rows' comments.
- Gender: never assume the person's gender where the language marks it; follow the glossary's approach.
- Don't change meaning; nutrition and medical text stays as careful as the English.
- Stored values, model prompts and logs are not in the rows; translate only what is listed.
- Do not edit any repository file.
```

## Translator (one per batch, in parallel)

```
You are a native <Language> (<market>) UI translator for Mivu, an iPhone food diary with a friendly fox coach called Pip. Translate a batch of app strings from English.

Read first: the glossary <REPO>/docs/languages/<code>.md. Input: <DIR>/batch-N.tsv (catalog, key, comment, english, current). The comment says where the text appears; use it.

<shared hard rules>

Output: <DIR>/out-N.json, a JSON array with one object per input row: {"catalog", "key" (exactly as in the TSV), "current" (exactly as in the TSV, usually ""), "proposed"}.
Before finishing, write and run a small Python check: the file loads, it has exactly one entry per input row, and each proposed value has the same placeholders as the english column, ignoring position numbers (a zero/one/two form may drop its number).
Reply only with the counts and the rows you were unsure about (key and a short reason).
```

## Pass 1: native reviewer (all strings)

```
You are a native <Language> speaker from <market> and an experienced app localizer: you know how the best local apps and Apple's own <Language> iOS read. Review the <Language> translation of Mivu, an iPhone food diary with a friendly fox coach called Pip. Find where it sounds translated, stiff, too formal, too long, unclear, or not how people there actually say it, plus outright errors, and propose better text.

Read all of <DIR>/rows.tsv, in chunks. Also read the glossary <REPO>/docs/languages/<code>.md and the store listing <REPO>/docs/app-store/listing.<code>.md (English: listing.md beside it; limits: name and subtitle 30, promotional text 170, keywords 100, description 4000).

<shared hard rules>

Report only real improvements, not taste swaps. Use the platform's own terms for tap, dictation, settings, iPhone and the like, as Apple writes them in <Language>.

Output: <DIR>/suggestions.json, objects {"catalog" (exact, or "listing.<code>.md"), "key" (exact), "current" (exact), "proposed", "reason" (one line in English), "severity": "error"|"improve"}. Also <DIR>/glossary.json for terms to change app-wide: {"term", "current", "proposed", "reason"}. Also <DIR>/code.json for shown text you notice bypassing translation: {"file", "line", "problem", "fix"}.
Before finishing, check with a script that every "current" matches the TSV exactly and placeholders are unchanged.
Final message (under 300 words): counts by severity, the 10 most important changes before → after, the glossary proposals, and a two-sentence verdict.
```

## Pass 2: placeholder reviewer (reads Swift)

```
You are a native <Language> speaker from <market>, an experienced app localizer, and you can read Swift. Mivu is an iPhone food diary with a fox coach called Pip. Check every string with a placeholder against the code that fills it: many sentences only break once the app fills in the value.

Repo: <REPO> (Swift under ios/Mivu, ios/MivuWidgets, ios/Shared). Inputs: <DIR>/placeholders.tsv (rows whose english has a placeholder) and <DIR>/rows.tsv for context. Glossary: docs/languages/<code>.md.

For each placeholder row:
1. Find its Swift caller(s): grep -rn a distinctive fixed part of the English. A key can have several.
2. Work out what each placeholder can hold: a word in <Language> (which?), a date starting with a digit, a weekday-led date, a number, a food name the person typed (any language, gender or number), a Latin name (ChatGPT, Apple), a unit, an already-translated sentence.
3. Read the sentence filled with realistic values. Flag it if it breaks for any of them: prefixes, articles or contractions before the value, case or agreement with a value of unknown gender or number, word order, a doubled word, number–noun agreement, plural forms that read wrong for small counts. If no wording works for every value, reword so the value stands alone (after a colon, or after a neutral noun such as "the date").
4. Flag shown text that bypasses translation: Label(String), Text(someStringVariable) holding English, a ternary choosing English words inside an interpolation, a plain ?? "English" fallback.

<shared hard rules>

Output: <DIR>/suggestions.json, objects {"catalog", "key", "current" (exact), "proposed", "reason" (one line naming the value that breaks it), "call_site" (file:line), "severity": "error"|"improve"}; code bugs to <DIR>/code.json as {"file", "line", "problem", "fix"}. Verify with a script that every "current" matches and placeholders are unchanged. Empty arrays are fine.
Final message (under 300 words): how many rows you traced (and which you could not), counts by severity, the important findings before → after, code bugs, and a two-sentence verdict.
```

To make `placeholders.tsv`: keep the header and the rows whose english column contains `%` or `${`.

## Pass 3+: final reviewer

```
You are a native <Language> speaker from <market>, an experienced app localizer, and you can read Swift. Earlier review passes have been applied to Mivu's <Language> text; this is a final pass. Find only what is still clearly wrong or clearly unnatural. Be restrained: no taste swaps. An empty result is a good result.

Read <DIR>/rows.tsv (all of it), the glossary docs/languages/<code>.md and docs/app-store/listing.<code>.md in <REPO>. Cover, in order:
1. Rows added or changed since the last pass: <list them, e.g. new feature strings>.
2. Placeholder rows the last pass did not trace: find the Swift caller and read them filled in.
3. A full read for wrong meaning, grammar, typos, gendered forms toward the person, glossary breaks, one English term translated two ways, and leftover formal register.
4. The listing, within its limits.

<shared hard rules>

Output: <DIR>/suggestions.json as in pass 1 (add "call_site" for placeholder rows) and <DIR>/code.json for text bypassing translation. Verify with a script.
Final message (under 250 words): counts by severity, every error before → after, improvements one line each, code issues, and a one-sentence verdict on whether the text is ready to ship.
```
