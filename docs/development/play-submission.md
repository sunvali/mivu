# Google Play submission (draft)

A draft for the owner. Nothing here has been entered in Play Console, and no
terms have been accepted.

No agent creates the account, accepts terms, signs with the upload key,
uploads, fills in Console forms or publishes. Steps marked **Owner** are done by
the owner, in the owner's own accounts. Check every answer against the live
Console form before you submit; Google changes the wording of its forms.
Answers marked **owner to confirm** are the ones the code alone cannot settle.

Sources: the [Android app design](../superpowers/specs/2026-10-23-android-app-design.md)
("Path to Google Play", "Play policy requirements"), the
[milestone 9 plan](../superpowers/plans/2026-10-25-android-play-readiness.md),
the [Phase 0 record](../verification/2026-10-23-android-phase0.md) and the
[milestone 9 record](../verification/2026-10-25-android-play-readiness.md). The
iOS counterpart is [app-store-submission.md](app-store-submission.md).

## Done in the app

- **Consent before ChatGPT.** Settings › Coach AI › Connect ChatGPT first shows
  "Share with OpenAI?", naming the data sent ("meals, photos, messages,
  weights, workouts, goals and profile details"). Sign-in opens only after
  "Agree and Continue" (`ChatGPTConnectButton.kt`, `ConnectionScreenTest`).
- **Privacy link.** Settings › Support links `MivuLinks.PRIVACY`
  (`https://mivuapp.com/privacy`).
- **"Estimates, not medical advice".** In Settings, on the onboarding targets
  step and in the empty Coach screen. Onboarding refuses birth years under 13,
  as on iOS.
- **Backup rules.** `data_extraction_rules.xml` excludes everything from cloud
  backup; device-to-device transfer carries only the diary database and files.
  ChatGPT credentials are Keystore-encrypted under `noBackupFilesDir` and never
  leave the phone (`BackupRulesTest`).
- **No debug code in release.** The proof, capture-probe and rig-preview
  activities live in `src/debug`; sample mode is a constant `false` in release
  (`ReleaseSmokeTest.releaseShipsNoDebugComponents`).
- **Report a Coach reply.** Long-press a Pip reply (or the TalkBack action) ›
  "Report reply" › pick a reason › Report. The report is saved on the phone and
  an email draft opens to `support@mivuapp.com`; without an email app the
  dialog offers "Copy address" and "Share" (`CoachReplyActionsTest`).
- **Target API 37**, compile SDK 37. Play requires API 36 for new apps from
  31 August 2026.
- **minSdk 31 (Android 12).** apilevels.com (read 2026-10-25) puts Android 12
  and 12L at about 9.9 % of devices, far above the 3 % cut-off. Lint runs before
  every Android push, so an unguarded Android 13 call cannot ship.
- **16 KB pages.** The release APK passes `zipalign -c -P 16`; every 64-bit
  native library is 16 KB-aligned.
- **Version code** comes from `android/play-uploads.txt` (`nextVersionCode`),
  checked by `scripts/ci/play_ledger.py`.

## Store listing (draft)

Copy follows [the App Store listing](../app-store/listing.md), with the iPhone
parts swapped for their Android counterparts. Recount after edits.

- **App name (30):** Mivu – Food Diary & Coach
- **Short description (80):** Log meals by photo or voice. Your food diary stays on your phone.
- **Category:** Health & Fitness (**owner to confirm**; Food & Drink is the
  alternative).
- **Contact email:** support@mivuapp.com (**Owner:** create the mailbox).
- **Privacy policy URL:** https://mivuapp.com/privacy (**Owner:** publish it).
- **App icon (512 × 512):** `design-system/mivu/precision-glass/icon/android/play-icon-512.png`.
- **Feature graphic (1024 × 500):** not made yet (**Owner**, or ask for one).

**Full description (4000):**

> Mivu is a private food diary with a friendly coach. Tell it what you ate in
> your own words, take a photo, or speak, and Mivu records the meal with
> estimated calories, protein, carbs and fat. Every estimate is yours to review
> and correct.
>
> LOG THE WAY YOU TALK
> • Describe a meal in plain language: "two eggs, toast and a coffee with milk".
> • Add photos of your plate, or speak and review the text before sending.
> • Record morning weight and workouts in the same conversation.
> • Ask Coach to fix an amount or a food, and it updates your diary.
>
> SEE YOUR DAY AT A GLANCE
> • Today shows calories and macros against targets that fit you.
> • The Diary keeps every day, with photo-led meal details.
> • Progress charts your weight and intake over time.
> • A home-screen widget shows calories left, with Snap It and Coach one tap away.
> • Log from the app icon's shortcuts, a Quick Settings tile, or by sharing a
>   photo or text into Mivu.
>
> MEET PIP
> Pip, Mivu's fox companion, sets up your daily targets in about a minute and
> reacts as you log. Pip respects the system's Remove animations setting.
>
> PRIVATE BY DESIGN
> • No Mivu account. Your diary and photos are stored on your phone.
> • No ads, no tracking, no analytics.
> • Export your diary and photos to a file at any time.
>
> AI THAT USES YOUR OWN PLAN
> Connect your ChatGPT account to estimate nutrition and chat with Coach.
> Requests use your ChatGPT plan, and you can manage usage or disconnect in
> Settings. Mivu asks before anything is shared with OpenAI.
>
> Nutrition figures are estimates, not medical advice. Talk to a health
> professional before making medical or dietary decisions.

**Release notes (500):** First release.

## Screenshots

Phone screenshots, 9:16 at 1080 × 1920 (Play: 2 to 8 images, each side 320 to
3840 px, the long side at most twice the short one). Taken on the emulator with
synthetic data; files in [`docs/verification/android-play/`](../verification/android-play/).

1. `play-01-today.png` — Your day at a glance (Today with Pip)
2. `play-02-coach.png` — Log a meal in your own words (Coach timeline)
3. `play-03-progress.png` — See how close you land (Progress)
4. `play-04-diary.png` — Your diary stays on your phone (Diary)
5. `play-05-widget.png` — Calories left on your home screen (widgets)

They are raw captures. Framing with brand teal and captions, as on iOS, is the
owner's choice. A photo-capture shot is not included: it needs a real meal photo
the owner has rights to.

## Data safety (draft answers)

**Owner ruling (2026-10-25): declare the data sent to OpenAI as shared.** The
user-initiated-transfer exception was considered and not taken.

How the app works, from the code:
- The diary (meals, photos, weights, workouts, goals, profile, Coach chat) is
  stored only on the phone, in the app's private storage. There is no Mivu
  server and no Mivu account.
- When the person connects ChatGPT and uses Coach, Mivu sends the turn's text
  and photos plus bounded diary context (profile, recent meals, weights,
  workouts, goal, recent Coach exchanges) to `api.openai.com` with the person's
  own ChatGPT token (`CoachContext.kt`, `ResponsesClient.kt`). Requests set
  `store: false`.
- Sign-in sends a random per-install host ID (`ext_agent_host_id`, a UUID) to
  `auth.openai.com` (`CredentialStore.hostID`, `OAuthAttempt.kt`).
- All network traffic is HTTPS. The only `http://` address is the sign-in
  callback on `127.0.0.1`, which never leaves the phone.
- No analytics, crash reporting, advertising or location SDK; no advertising ID.

**Overview questions**

| Question | Draft answer |
|---|---|
| Does your app collect or share any of the required user data types? | Yes |
| Is all of the user data collected by your app encrypted in transit? | Yes (HTTPS only) |
| Do you provide a way for users to request that their data is deleted? | Yes: in-app deletion of each meal, photo, weight and workout; Disconnect ChatGPT; Android's Clear storage or uninstall erases everything. Mivu holds no copy elsewhere. **Owner to confirm** how to describe data already sent to OpenAI under the person's ChatGPT account. |
| Account creation | The app does not let users create an account. ChatGPT sign-in is OpenAI's account, so account deletion does not apply. |

**Data types** — each is collected and shared with OpenAI, only when the person
uses Coach with ChatGPT connected; optional (the diary works without it); for
App functionality; not used for tracking, ads, analytics or personalization by
Mivu.

| Play data type | What Mivu sends | Collected | Shared | Ephemeral | Required |
|---|---|---|---|---|---|
| Photos and videos › Photos | Meal photos attached to a Coach turn | Yes | Yes | No (**owner to confirm**: `store: false`, but OpenAI's retention applies) | Optional |
| Health and fitness › Health info | Weight entries, height, birth year, sex, pace, calorie and macro goals, diet preferences | Yes | Yes | No (as above) | Optional |
| Health and fitness › Fitness info | Logged workouts (kind, minutes) | Yes | Yes | No (as above) | Optional |
| App activity › Other user-generated content | Coach messages and meal names and notes | Yes | Yes | No (as above) | Optional |
| Personal info › Name | The profile name, part of the profile in the Coach context (**owner to confirm**: it is often a nickname, but it is sent) | Yes | Yes | No (as above) | Optional |
| Device or other IDs | The random per-install `ext_agent_host_id` sent at sign-in (**owner to confirm** whether Play counts it) | Yes | Yes | No | Optional |

**Not collected:** location, contacts, financial info, calendar, files and docs,
web browsing, app interactions, crash logs, diagnostics, advertising ID.

**Voice input** uses Android's system speech recognizer; Mivu receives only the
transcribed text, which then goes into the message like typed text. The audio
is handled by the phone's speech service, not by Mivu. **Owner to confirm**
that Audio › Voice or sound recordings is "not collected".

**Coach reply reports** are saved on the phone and sent only when the person
sends the email draft themselves; they go to Mivu's own mailbox, not a third
party.

## Health apps declaration (draft)

- Features: nutrition and calorie tracking; weight management; activity
  (workout) logging.
- Not a medical device; no diagnosis, treatment or medical claims.
- Disclaimers in the app: "estimates, not medical advice" in Settings, on the
  onboarding targets step and in the empty Coach. Onboarding keeps weight-loss
  targets to a healthy BMI (not below 18.5), at most 0.75 kg a week, and never
  below 1200 kcal; minimum age 13.
- No Health Connect access and no health permissions are requested.

## AI-generated content (draft)

- Coach replies are generated by OpenAI models through the person's own
  ChatGPT account. The owner ruled the AI-generated content policy applies.
- In-app reporting: long-press a Pip reply (or use the TalkBack action) ›
  "Report reply" › reason and optional note › Report. The report is saved on the
  phone and an email draft opens to support@mivuapp.com. **Owner:** create that
  mailbox and read it before release.
- Coach's instructions treat user text and retrieved content as data, keep
  replies short, and never state numbers it did not read.

## Account deletion

Not applicable: Mivu creates no account. The diary is local; ChatGPT sign-in is
OpenAI's account. Data deletion: Settings › Coach AI › Disconnect ChatGPT
(deletes the stored tokens and revokes them), per-item delete in the app, and
Android Settings › Apps › Mivu › Storage › Clear storage (or uninstall). Owner
to confirm in the Console.

## App access (reviewer instructions, draft)

> Mivu is a private food diary. Diary data is stored only on this phone. Meal
> entry, editing, history, progress, widgets, export and reports work without
> any account.
>
> Coach uses the person's own ChatGPT account. To test it: Settings › Coach AI ›
> Connect ChatGPT › Agree and Continue, then sign in to ChatGPT in the browser
> tab with the test account below. When the page says "You can return to Mivu",
> press Back. Open the Coach tab and send "two boiled eggs and a slice of
> toast"; Pip saves the meal and replies.
>
> Test ChatGPT account: `<email>` / `<password>`

**Owner:** Phase 0 item 6 is still blocked. The account must sign in without a
one-time code the reviewer cannot receive, and the owner must authorize a paid
plan for it.

## Other Console forms (draft)

- **Content rating (IARC):** reference app / utility; no violence, sexuality,
  profanity, drugs or gambling; users do not interact with each other; no
  location sharing; generated text from an AI chatbot (answer the AI question
  "yes"). **Owner to confirm** the rating the questionnaire returns.
- **Target audience:** 13 and over (onboarding enforces it); not designed for
  children. **Owner to confirm** whether to choose 18+ to avoid Families
  questions.
- **Ads:** no ads.
- **News app:** no. **Government app:** no. **Financial features:** none.
- **COVID-19 / health research:** no.

## Closed test

- At least 12 testers opted in for 14 continuous days, on personal Play
  accounts created after 13 November 2023 (the rule for new personal developer
  accounts).
- The test starts only after Phase 0 items 2–5 pass on the physical phone (the
  [milestone 9 record](../verification/2026-10-25-android-play-readiness.md),
  "Physical phone").
- Testers need their own ChatGPT accounts for Coach; the rest of the app works
  without one.
- Applying for production is the owner's decision after the 14 days.

## Release steps (Owner)

1. Create the upload keystore with `keytool`, keep it and its passwords outside
   the repo, and set `MIVU_UPLOAD_STORE_FILE` (absolute path),
   `MIVU_UPLOAD_STORE_PASSWORD`, `MIVU_UPLOAD_KEY_ALIAS` and
   `MIVU_UPLOAD_KEY_PASSWORD` in `~/.gradle/gradle.properties`.
2. `cd android && ./gradlew :app:bundleRelease`.
3. Install the same AAB on the phone with bundletool
   (`build-apks --connected-device`, then `install-apks`) and run the release
   checks in the record's "Physical phone" section.
4. Upload the AAB to the internal or closed track in Play Console, and enroll
   in Play App Signing.
5. Add the ledger line `code name sha date track` to `android/play-uploads.txt`,
   run `python3 scripts/ci/play_ledger.py android/play-uploads.txt`, and commit
   it.
6. Read the pre-launch report.
