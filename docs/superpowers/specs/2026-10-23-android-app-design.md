# Mivu for Android: design

Status: draft for owner approval, 2026-10-23. Revised the same day after
review: Phase 0 ChatGPT proof, Play policy checks, version codes, archive
compatibility, durable capture, matrix rules, backup/restore and Android
quality checks. Policy and platform claims checked against official docs on
2026-10-23 are cited; anything not confirmed is marked **unverified**.

## Intent

The owner wants Mivu on Android, published on Google Play, with the same
features as the iPhone app. Mivu on iPhone looks and behaves like a native iOS
app. Mivu on Android must look and behave like a native Android app, not a
port of the iOS screens. The owner also wants to know at any time which
features each platform has and where they differ, so the two apps can be kept
in step as both keep growing.

## Owner decisions

- **Stack:** fully native Kotlin with Jetpack Compose. No code is shared with
  iOS. iOS stays Swift/SwiftUI and is not rewritten.
- **Repository:** an `android/` folder in this repository, next to `ios/`.
- **Look:** Material 3 Expressive (Google's current native design language)
  with Mivu's brand: Precision Glass colors, Pip, and the same words. Android
  structure and controls: top app bar, short navigation bar, predictive back,
  edge-to-edge layout, Roboto, and Material Symbols. Not a copy of the iOS glass look.
  The approved mockup is direction B in
  [android-mockups.png](../../verification/android-design/android-mockups.png).
- **First Play release:** full parity with iOS as of `main` at commit
  `dd5e8c34` (the *parity baseline*). iOS work merged after that commit
  shows as "Android pending" in the parity matrix and does not block the
  first release.
- **Pip:** the same rig source as iOS, drawn natively in Compose.
- **Minimum Android version:** Android 12 (API 31). Target SDK is whatever
  Play requires at submission time.
- **Builds and tests:** local only, like iOS. Hosted CI stays Linux script
  checks within the existing two-minute limit. No hosted Android builds.
- **ChatGPT sign-in:** the same auth.openai.com authorization contract as iOS.
  If it cannot be proven live on Android, or is not allowed, the Android
  release waits. No paid API, API key, or sample-mode substitute.
- **iOS-only system features** get Android equivalents (mapped below), not
  omissions.
- **After launch:** a feature may ship on either platform first. Its matrix
  row shows the other platform as pending, so the gap is always visible.
- **Starting point:** no Play Console account, no Android phone, no Android
  tooling on this Mac yet.
- **Closed test** starts only after ChatGPT sign-in works on Android, so
  testers get a Coach that really analyzes food.
- **Screens beyond Today and Coach** (Diary, Progress, onboarding, settings,
  widgets and the rest): rendered Android mockups beside the iPhone screens
  are approved by the owner before each milestone's screens are built.
- **Android system backup:** device-to-device transfer includes the diary,
  Google cloud backup excludes it, and ChatGPT tokens are excluded from both.
  The user's own backups remain the chosen folder and the archive.

## Goals

1. A Play-listed Android app with every baseline iOS feature, at the same
   quality bar (Apple/Google-level polish, not just "works").
2. One place that shows the iOS/Android status of every feature, kept honest
   by CI.
3. Diaries move between platforms: an archive exported on one imports on the
   other.

## Non-goals

- Shared Kotlin Multiplatform or Compose Multiplatform code.
- Changing iOS behavior to suit Android. iOS changes are limited to what the
  shared contracts need (for example, a shared test fixture). Each such change
  goes through the iOS rules in AGENTS.md.
- Tablets, foldables-specific layouts, Wear OS, Android Auto, Chromebooks.
  Phones only. Mivu must still not break on large screens, using Compose's
  default adaptive behavior.
- Hebrew/RTL. English only, matching the iOS MVP rule. Stored language values
  in archives are preserved untouched.
- Cloud sync or a server.

## Anti-goals (failure even if it "works")

- Looks like an iPhone app on Android: glass blur, iOS chevrons, iOS
  sheet/back patterns, SF-style icons.
- Diverges silently: a feature that exists on one platform with no matrix
  row, or a row that claims parity without recorded passing evidence.
- Loses a user's input. Durable local capture is as strict as on iOS: save
  first, analyze later, never restore stale data over deletions.
- Claims "published" or "works with ChatGPT" without observed evidence.

## Shared contracts (what keeps the two apps in step)

The apps share specifications and data, not code:

| Contract | Source of truth | Android use |
|---|---|---|
| Product behavior | Existing specs in `docs/superpowers/specs/` and `docs/development/` (Coach chat behavior, Coach edit parity, day rollover, onboarding, etc.) | Same behavior; Android-specific notes go in each feature's Android spec section or the matrix notes |
| Diary archive | `mivu-diary` envelope, version 4 (`ios/Mivu/Diary/DiaryArchive.swift`) | Android reads and writes the same format; see [Archive compatibility](#archive-compatibility) |
| Visual tokens | `design-system/mivu/precision-glass/tokens.json` | Mapped into a Material 3 color scheme (light, dark, high contrast). Brand colors are fixed; dynamic (wallpaper) color is off |
| Pip art | `design-system/mivu/characters/pip/rig/pip.svg`, then `build.py`, then `pip-rig.json` | The same generated JSON, bundled as an Android asset |
| Pip motion | iOS `PipGestureLibrary` and the motion tokens | Same gestures, timings and poses |
| Analysis | The iOS inference request/response contract (`ios/Mivu/Analysis`) | Same prompts, parsing rules and failure reasons; analysis stays separate from meal calculations (AGENTS.md) |
| Test inputs | Synthetic only | Shared synthetic fixtures (archive samples, model responses) live in one folder that both test suites read |

### Archive compatibility

An archive is the user's only cross-platform path, so it must lose nothing.

- **Both directions are tested.** A synthetic archive exported by iOS imports
  on Android, and one exported by Android imports on iOS. Each side checks the
  result against the same expected snapshot. Each direction is its own test:
  an Android unit test reading the iOS-made fixture, and an iOS unit test
  reading the Android-made fixture (a small iOS test-only PR).
- **Legacy versions:** committed synthetic fixtures for versions 1, 2, 3 and 4
  import on Android exactly as on iOS, including the version-4-only rule for
  manual acceptance. Unknown formats or versions are rejected without touching
  existing data.
- **Preserved field by field:** profile and record identifiers (UUID values
  are compared as values, case-insensitively, and written the way iOS writes
  them); dates as the same instants (iOS `JSONEncoder` writes `Date` as
  seconds since 2001-01-01 UTC, not the Unix epoch); every other date,
  time-zone and waking-day field the snapshot carries; all nutrition numbers without rounding drift; photo bytes identical
  (compared by hash); stored language values; deletions and receipts.
- **Limits:** the same 350 MB cap. Android parses the file as a stream, so a
  large archive does not exhaust memory.
- **Owner check:** the profile identifier check behaves as on iOS (wrong
  owner is refused).

### Durable capture and analysis

These rules restate the iOS rules from AGENTS.md and the
[Coach chat history plan](../plans/2026-10-18-coach-chat-history.md) for
Android.

- **Save before anything else.** A capture is acknowledged ("saved on this
  phone") only after its photo file is written and flushed in app storage and
  its database row is committed in one transaction. A crash between the two
  leaves either nothing acknowledged or a complete capture. Orphan photo files
  are cleaned up at startup.
- **Recovery after process death:** at startup, and through WorkManager,
  every committed capture without a committed result is found again and
  re-queued. Nothing lives only in memory or only in a WorkManager job.
- **Retry deduplication:** each capture gets an immutable ID when it is
  saved. Every analysis attempt carries that ID. A result is applied at most
  once per capture: applying it and recording the receipt happen in one
  transaction, and a second result for a capture that already has a receipt
  is ignored. Uncertain attempts are reconciled with the same payload and
  never re-sent as a new capture.
- **No stale overwrites:** a request records the meal's revision when it
  starts. If the meal was edited since then, the result does not overwrite
  the edit; it is handled as iOS handles that case (the builder copies the
  rule from the baseline code and Coach behavior contract). If the meal was deleted, the
  deletion wins and the result is discarded. Restores and retries never bring
  back a deleted meal.
- **Tests:** unit tests for each rule, plus one instrumented test that kills
  the process between save and analysis and checks recovery.

## The parity matrix

One Markdown file, `docs/parity.md`, readable on GitHub and on a phone. One
row per user-facing feature:

| Column | Meaning |
|---|---|
| ID | Short stable slug, e.g. `coach-photo-capture` |
| Feature | Plain-English name |
| Scope | `baseline` (in the `dd5e8c34` parity baseline, so it blocks the first Android release) or `post-baseline` (tracked, does not block) |
| Spec | Link to the spec or behavior doc |
| iOS | Status |
| Android | Status |
| Evidence | Per platform: link to the `docs/verification/` record that shows the named tests passing |
| Notes | Android equivalent used, known differences, blocked gates |

Statuses: `done` (implemented, and the named tests are recorded as passing),
`partial` (notes say what's missing), `pending`, `equivalent` (done by a
different native mechanism, named in notes), `blocked` (external gate, named
in notes), `n/a` (deliberately absent, with the reason).

`done` and `equivalent` need recorded passing evidence, not just test names.
The linked verification record names the tests and gives the exact source
SHA, environment (device or emulator and OS/API level), and pass/fail/skip
counts, following AGENTS.md. A test that exists but has no recorded passing
run does not count. Skipped or blocked tests never count.

**Release gate:** the first Android release needs every `baseline` row to be
`done` or `equivalent` on Android, or `n/a` with the owner's recorded
approval. `post-baseline` rows never block it.

**CI check** (Python standard library, runs in the existing `checks` job):

- the table parses, IDs are unique, and scope and status values are from the
  lists;
- every `done`/`equivalent` cell links an existing verification record that
  mentions each named test and a 40-character source SHA. CI checks only that
  the record exists and is consistent. It cannot prove a run took place; the
  record is the local evidence, as for iOS today;
- any PR of any type that changes `ios/`, `android/`, `fixtures/`,
  `design-system/mivu/`, or a shared-contract source (archive, analysis
  contract, Pip rig) must also change `docs/parity.md` or carry the line
  `Parity: unchanged - <reason>` in its description. That catches fixes,
  refactors, asset changes and contract changes, not just `feat` PRs.

The first version of the matrix lists every baseline feature below, with iOS
statuses and evidence links taken from the existing verification records.
Baseline features with no iOS evidence record are listed as iOS `partial`,
not `done`.

## Feature map at the parity baseline

Each row is one matrix row. *Android approach* is the native mechanism, not a
spec of its behavior; behavior comes from the linked iOS spec.

| Feature (iOS) | Android approach |
|---|---|
| Onboarding hosted by Pip, sets daily targets | Compose flow, same steps and target math |
| Today: waking-day summary, kcal, macros, pending, meals, Log meal | Compose screen, direction B |
| Day rollover and morning check-in | Same rules. Scheduling uses WorkManager and AlarmManager only where exact timing is required |
| Diary: week strip, photo-led meal detail, foods editable from Coach | Compose screens, predictive back |
| Meal composer, manual nutrition, review and correction | Compose, Material 3 bottom sheets and text fields |
| Coach: text and photo capture, saved locally before analysis, retry | Committed local save before any network; WorkManager runs analysis and retries; rules in [Durable capture and analysis](#durable-capture-and-analysis) |
| Coach chat history (100-exchange window, bounded queries, jump to latest) | Lazy list with the same bounded paging rules; Material floating "Jump to latest" button with the same spoken label |
| Coach: reply to a message or Diary record | Same behavior |
| Coach understands intent and acts on it (context) | Same contract and operations |
| Coach voice logging and the redesigned composer | Android `SpeechRecognizer` (on-device where available) behind the same composer design |
| Every manual edit also works through Coach (edit parity) | Same rule, same tests per operation |
| Progress: goals, weight, analytics, charts, plateau readiness | Same calculations; charts drawn in Compose Canvas (no chart library unless Canvas proves insufficient) |
| ChatGPT connection: consent, sign-in, model selection, revoke, connect from anywhere | Custom Tabs plus an HTTP loopback listener on `127.0.0.1` (never `localhost`), the same auth.openai.com contract, and JWKS ID-token validation; proven first in [Phase 0](#phase-0-chatgpt-proof-release-gate). Tokens encrypted with an Android Keystore key, kept out of every backup and transfer ([Backup and restore](#backup-and-restore)) |
| OpenAI data consent | Same consent screen and stored decision |
| Settings, profiles, daily targets | Compose settings screens |
| Backup to a chosen folder | Storage Access Framework folder picker with a persisted permission. It works with any storage provider that offers folder picking. Whether Google Drive does is **unverified**: a community report says Drive doesn't support the folder (tree) picker, so test it on a real phone before any wording mentions Drive. Where folder picking isn't offered, archive export to a single file (which providers widely support) still works. Same "saved to folder ≠ synced" wording |
| Archive export and import | Same `mivu-diary` format via the system file picker and share sheet |
| Diary reports as PDF or CSV | Android `PdfDocument` plus CSV, shared through the system share sheet |
| Notification when a logged meal is analyzed | Android notification channel; asks for notification permission (Android 13+) at a meaningful moment |
| Quick capture: Shortcuts, Action button, Home Screen quick actions | Launcher app shortcuts (Log food, Coach), a Quick Settings tile, and "Share to Mivu" for text and photos |
| Widgets: calories, Log Food, Coach | Jetpack Glance home-screen widgets |
| Live Activity: calories left in the Dynamic Island | **My call:** the calories widget covers "glanceable calories left". Android 16 Live Updates are meant for time-bound tasks and likely don't fit an all-day counter, so the row is `n/a` with that reason unless research during build shows Live Updates allow it |
| Pip: layered rig, gestures, blink, moments | Compose Canvas renderer over `pip-rig.json`; the system "Remove animations" setting gives the static pose (the iOS Reduce Motion rule) |
| App icon (Pip portrait) | Adaptive icon (foreground, background, monochrome for themed icons) from the same art |
| Sample mode (`--sample-mode`) | Same clearly labeled synthetic estimate, enabled only from a debug launch flag |
| Privacy manifest and App Review readiness | Play Data safety form, privacy policy link, health apps declaration, content rating, reviewer sign-in access; see [Play policy requirements](#play-policy-requirements) |
| *(compliance, not on iOS)* Report a Coach reply | Only if Play's AI-generated content policy applies (see [Play policy requirements](#play-policy-requirements)): an in-app way to report or flag an offensive Coach reply without leaving the app. Its own matrix row; iOS status decided separately |

Untracked drafts in this working copy (Siri-to-Coach, the 2026-10-23 Coach
reply revision) are after the baseline: matrix rows with Android `pending`.

## Android-specific quality rules

- Accessibility: TalkBack labels matching the iOS spoken labels, font scaling
  to 200% without clipping (stack, don't shrink), 48 dp minimum touch targets
  (Android's standard, larger than iOS's 44 pt), contrast at least 4.5:1, and
  the system "Remove animations" setting.
- Edge-to-edge with correct insets, predictive back on every screen, gesture
  and 3-button navigation both verified.
- Light, dark and high-contrast color schemes from the tokens.
- Process death: every screen restores. Unsent composer text survives, as on
  iOS.
- Credentials never logged, never in backups, never in the APK.
- **Large screens and resizing (minimal check, not support):** phones are the
  only supported form factor. Once per release candidate, one tablet-size
  emulator run checks that the main screens show no crash, no clipped or
  unreachable content, and no lost state across rotation, split-screen and
  window resize. For apps targeting API 36, Android 16 ignores orientation,
  resizability and aspect-ratio restrictions on displays at least 600 dp
  wide
  ([Android](https://developer.android.com/about/versions/16/behavior-changes-16)),
  so the app must not depend on portrait lock. Fixes stay within Compose's default adaptive behavior; no
  tablet layouts.
- **Real device:** at least one physical Android phone before the closed
  test. It runs Phase 0, camera and photo picker, voice input, notifications,
  widgets, quick capture, folder backup with the providers actually available,
  device-to-device restore, and a performance pass. Emulator evidence does not
  replace any of these.
- **Release build:** every release candidate is verified as the signed
  release build (R8 shrinking on), not just the debug build. Install it on
  the physical phone from the same AAB that will be uploaded (for example via
  bundletool), then smoke-test sign-in, capture, analysis, archive
  export/import and widgets. Review Play's pre-launch report for every
  uploaded build. Evidence records the AAB's version code and source SHA.

## Build, test and evidence

- Kotlin, Compose, Material 3, Room (or plain SQLite if Room fights the
  archive contract), WorkManager, Glance, Navigation with typed routes.
  Platform and Jetpack libraries first; every other dependency is justified
  in the PR.
- Gradle wrapper committed. Version name comes from the repo's existing
  `version.txt`, so release-please keeps one Mivu version for both platforms.
- **Version code (unique per upload):** Play rejects a version code it has
  already seen, and every new upload needs a higher one. The version code is
  therefore not derived from the version name. A committed ledger,
  `android/play-uploads.txt`, has one line per AAB uploaded to Play:
  version code, version name, source SHA, date and track. A release build
  uses *last version code + 1*, and the build fails if the ledger is
  missing or not increasing. A replacement build of the same version (for
  example 1.4.0 rebuilt after a fix) gets the next code. The ledger line is
  committed right after each upload. If someone forgets, Play's own duplicate
  check rejects the next upload, so the mistake cannot ship. Debug builds use
  a fixed code of 1 and are never uploaded.
- Local verification mirrors iOS: Gradle unit tests for logic, Compose UI
  tests on an emulator for screens and navigation, with exact source SHA,
  device/API level, and result counts recorded in `docs/verification/`.
  Emulator results do not prove camera, sign-in, or notifications on a real
  phone; those stay `blocked` until tested on a physical device.
- Git hooks: native Android unit tests run on push only when `android/`
  inputs changed, the same pattern as iOS.
- AGENTS.md gains a short Android section: Gradle and emulator in place of
  XcodeBuildMCP, same evidence and honesty rules.

## Path to Google Play

1. **Owner:** install Android Studio and accept the Android SDK licenses
   (owner-only legal terms). Create an emulator.
2. **Phase 0: ChatGPT proof** (below). It comes before the skeleton. If it
   fails, the release is blocked, as the owner decided.
3. Build to parity in milestones (exact plan to follow). Suggested order:
   skeleton, theme and matrix; storage and archive; Today and Diary with
   sample mode; Coach capture and history; ChatGPT connection; Progress,
   onboarding, rollover, notifications and reports; Pip; widgets, quick
   capture and voice.
4. **Owner:** settle the account type (see below), then create the Google Play
   developer account, pay the fee, and complete verification. Claude never
   does this.
5. Upload signing: a local upload key the owner keeps, plus Play App Signing.
   Builds are produced locally as an AAB with a version code from the ledger.
6. **Closed test:** personal accounts created after 13 November 2023 need a
   closed test with at least 12 testers opted in continuously for at least
   14 days before applying for production
   ([Google](https://support.google.com/googleplay/android-developer/answer/14151465)).
   That page does not say whether organization accounts are exempt
   (**unverified**). By owner decision the test starts only after sign-in
   and real analysis work on Android (Phase 0 items 2 to 5). The owner recruits the testers.
7. Store listing, screenshots (from the emulator in direction B), and the
   policy items below, prepared in the repo. The owner submits.
8. Apply for production access, then publish. Only on the owner's explicit
   go-ahead.

### Phase 0: ChatGPT proof (release gate)

Goal: prove, on Android, everything the release depends on from OpenAI before
building the rest. Run it on an emulator first and then on the physical phone.
Diagnostics use synthetic inputs. The live meal check uses a test meal photo,
not personal diary data. Record the evidence in `docs/verification/`. Each
item passes or is marked `blocked`:

1. **Eligibility (external).** OpenAI's quickstart says ChatGPT plan usage is
   "available to all open-source partners and selected private clients".
   Paid or remotely hosted apps are pointed to an interest form
   ([quickstart](https://developers.openai.com/siwc/quickstart),
   [overview](https://developers.openai.com/siwc/token-sharing-open-source)).
   The docs say nothing about closed-source apps distributed through app
   stores. Mivu's repository is private, so confirm with OpenAI in writing
   that a Play-distributed Mivu may use this flow. This same question applies
   to the iOS release.
2. **Authentication.** Checked against the
   [sign-in docs](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
   and matching the iOS code at the baseline:
   - an HTTP loopback redirect `http://127.0.0.1:<port>/auth/callback`; only
     the port may vary between sign-ins, never `localhost`, and the path must
     match exactly;
   - the listener starts before the browser opens, and the same URI (port
     included) is sent in the authorization request and the code exchange;
   - PKCE S256 with a fresh verifier, plus `state` and `nonce`;
   - first registration uses `client_id=dynamic_agent_client` with
     `agent_name_hint=Mivu`; the issued client ID is saved and used for every
     later sign-in and the token exchange, and `agent_name_hint` is not sent
     again;
   - `ext_agent_host_id` is distinct per host and persisted before the first
     sign-in.

   The Android-specific risk to prove is that the redirect from a Custom Tab
   reaches the app's `127.0.0.1` listener reliably on a real phone, including
   when the app goes to the background during sign-in.
3. **Authorized inference:** one Responses request with the documented
   limits (`store: false`, `stream: true`, unsupported fields omitted)
   ([limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)).
4. **Real analysis:** one text meal and one meal photo analyzed end to end
   into a diary entry, with a model that accepts image input. The docs say
   image input works only "when the selected model accepts them".
5. **Token refresh:** a refresh replaces the access token, expiry, scopes and
   rotating refresh token together. `invalid_grant` / `refresh_token_reused`
   and similar errors clear the tokens and ask the user to sign in again; a
   temporary network failure never erases credentials
   ([errors](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery)).
   The refresh request itself is not on those pages; follow the iOS
   implementation and the token reference page.
6. **Reviewer access path.** Play requires sign-in details that work at all
   times and from any location, and for third-party sign-in the account
   details plus step-by-step instructions
   ([Google](https://support.google.com/googleplay/android-developer/answer/15748846)).
   Mivu's core features need a ChatGPT plan account (the docs name eligible
   Plus and Pro users). Prove that a dedicated reviewer ChatGPT account can
   complete sign-in and analysis without a one-time code the reviewer can't
   receive, or document the path Play accepts for it. **Unresolved:** a paid
   reviewer account needs the owner's authorization, and whether that account
   needs email codes, and whether OpenAI's terms allow it, are unverified.

Exit: items 2 to 5 pass on the physical phone, and items 1 and 6 have a
written answer. Otherwise the release stays blocked.

### Play policy requirements

Checked 2026-10-23. **Unverified** marks what the docs did not settle.

- **Account type (unresolved).** Play Console Requirements says developers
  providing "Health apps, such as Medical apps and Human Subjects Research
  apps" must register as an organization
  ([Google](https://support.google.com/googleplay/android-developer/answer/10788890)).
  Google's health categories put nutrition trackers under "Health and
  fitness", separate from "Medical"
  ([Google](https://support.google.com/googleplay/android-developer/answer/13996367)),
  but neither page says whether health-and-fitness apps need an
  organization account. Ask Google Play support before creating the account.
  An organization account needs a D-U-N-S number and business verification.
- **Target API:** from 31 August 2026, new apps and updates must target API
  36 (Android 16)
  ([Android](https://developer.android.com/google/play/requirements/target-sdk)).
- **Health apps declaration:** filled in the Play Console App content page.
  Whether Mivu's listing also needs a "not a medical device" disclaimer
  depends on the category answer (**unverified**).
- **Privacy policy:** linked in Play Console and inside the app.
- **Data safety:** declare what Mivu collects and where it goes: meal text,
  photos, nutrition and weight (health and fitness info), and the ChatGPT
  connection. Whether sending data to OpenAI under the user's own account
  counts as "sharing" is decided against Google's Data safety definitions,
  with the reasoning recorded in the repo. The answers must match the
  backup rules below and the Phase 0 behavior.
- **AI-generated content:** Google's guidance puts "text-to-text AI chatbot
  apps, in which the AI generated chatbot interaction is a central feature"
  in scope and AI that enhances an existing feature out of scope
  ([Google](https://support.google.com/googleplay/android-developer/answer/14094294)).
  The policy requires in-app reporting or flagging of offensive AI output
  without leaving the app. Whether the Coach counts as "central" is
  **unverified**. If it is in scope, Android adds the "Report a Coach reply"
  row. **Open:** where reports go, given the non-goal of having no server.
  That needs an owner decision.
- **App access:** reviewer sign-in details as in Phase 0 item 6.
- **Content rating** questionnaire.

## Backup and restore

- **Android system backup** (owner decision): the data extraction rules
  include the diary database and photos in `<device-transfer>`, exclude them
  from `<cloud-backup>`, and exclude everything from
  `<cross-platform-transfer>`. That last one is my call: iOS Mivu cannot use
  it, and a missing section means "transfer everything"
  ([Android](https://developer.android.com/identity/data/autobackup)).
- **Credentials:** encrypted tokens and the issued client ID live in
  `noBackupFilesDir` (always excluded). Android Keystore keys
  are expected not to leave the device (**unverified** wording; the backup
  page doesn't cover Keystore), so encrypted credentials would be useless
  anyway. After any restore the user is signed out and reconnects.
- **Per-install identity:** `ext_agent_host_id` is never backed up or
  transferred. A restored phone is a new host and creates a new one, because
  OpenAI requires a distinct host ID per host and Android's guidance is to
  exclude device-specific identifiers.
- **Permissions:** folder-backup access (a persisted document permission) and
  notification permission don't carry over. After a restore the backup
  status shows "Choose the backup folder again". It never claims the old
  folder is still in use.
- **Pending analysis:** restored captures stay pending. WorkManager jobs
  don't transfer, so the startup scan re-queues them. They wait for the user
  to reconnect ChatGPT and then follow the dedup and stale-result rules. A
  restore never brings back a deleted meal.
- **Tests:** an instrumented test runs backup and restore with `bmgr`
  (cloud excluded, transfer included) and checks the rules above. A real
  device-to-device transfer is tested once on physical phones before
  release, if two phones are available; otherwise it is recorded as
  `blocked`.

## Risks and open gates

External blockers (**unresolved**; each blocks the release until it has a
written answer):

- **OpenAI eligibility** for a closed-source, Play-distributed app (Phase 0
  item 1). It applies to iOS too.
- **Reviewer access** with a ChatGPT plan account (Phase 0 item 6).
- **Play account type:** whether a nutrition tracker needs an organization
  account.
- **AI-content reporting:** whether it applies, and where reports go.
- **Physical Android phone:** none yet. Phase 0, camera, voice,
  notifications, widgets, restore and the release-build check need one.

Other risks:

- **ChatGPT sign-in on Android** is unproven, as it still is live on iOS. It
  blocks release by owner decision. Phase 0 proves it first.
- **Play policy for health and nutrition apps:** the health declaration and
  Data safety answers must match what the app actually sends to OpenAI.
- **Google Drive folder backup** may not be available (see the feature map).
- **Closed-test clock:** 14 days of calendar time plus Google's review time.
- **Parity drift during the build:** iOS keeps shipping. The baseline pins
  the first-release scope, and the matrix shows everything after it.

## Settled details (my calls unless marked)

- **Baseline source:** the code, specs and verification records at
  `main@dd5e8c34` are authoritative. Android work branches from `main`, not
  from older local branches. The matrix's iOS column is filled from the
  verification records at that commit.
- **Sign-in identity:** Android mirrors the iOS request, with the same fields
  and agent name hint, and the same `http://127.0.0.1:<port>/auth/callback`
  redirect. iOS picks any free port, which the docs allow; only the port may
  vary. Android uses its own locally generated host ID per install. Phase 0
  comes first in the plan, ahead of the skeleton, because it gates the
  release.
- **Shared fixtures:** a top-level `fixtures/` folder holds synthetic data.
  Android reads it from the start. The two-way archive proof
  ([Archive compatibility](#archive-compatibility)) needs a synthetic archive
  exported by iOS, plus an iOS import test of an archive exported by
  Android. That is a small iOS test-only PR under the iOS rules. Android
  storage work does not wait for it, but the archive row cannot be `done`
  without it.
- **Pip evidence:** an Android unit test compares sampled poses (part
  transforms at fixed times per gesture) against a golden fixture exported
  once from the iOS `PipGestureLibrary` by a small iOS test-only PR.
- **Background analysis:** match iOS. Analysis runs while the app is open.
  Queued and retried work uses expedited WorkManager. No foreground service,
  so no extra Play policy surface. No latency promise beyond iOS behavior.
- **Version code:** taken from the upload ledger (see Build, test and
  evidence), never computed from the version name.

## Left to the builder

- Module layout inside `android/` (start with one app module plus a widget
  module only if Glance needs it).
- Room versus plain SQLite, chart drawing details, and the exact Compose
  structure of each screen within direction B and the Material 3 Expressive
  guidelines.
- Exactly how the matrix checker detects test names.
- How Pip gestures reach Android: a careful Kotlin port checked against iOS
  timings, or extracting them to shared data. Either way iOS behavior must
  not change without its own reviewed PR.
