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
  (`https://mivuapp.com/privacy/android`, the Android policy; `/privacy` is the
  iPhone one and stays as it is).
- **"Estimates, not medical advice".** In Settings, on the onboarding targets
  step and in the empty Coach screen. Onboarding refuses birth years less than
  18 years back (iOS: 13). It asks for the year only, so someone who turns 18
  later this year can pass; **owner to decide** whether to ask for the month.
  "Later" skips setup, so the gate is a safeguard inside setup; the 18+ answer
  under Target audience is what declares the audience.
- **Backup rules.** `data_extraction_rules.xml` excludes everything from cloud
  backup; device-to-device transfer carries only the diary database and files.
  ChatGPT credentials are Keystore-encrypted under `noBackupFilesDir` and never
  leave the phone (`BackupRulesTest`).
- **No debug code in release.** The proof, capture-probe and rig-preview
  activities live in `src/debug`; sample mode is a constant `false` in release
  (`ReleaseSmokeTest.releaseShipsNoDebugComponents`).
- **Report a Coach reply.** Long-press a Pip reply (or the TalkBack action) ›
  "Report reply" › pick a reason › Report. The report is saved on the phone and
  sent in the app to `https://reports.mivuapp.com/` (the mivu-infra worker,
  which emails it to the owner), so the person never leaves Mivu. If it cannot
  be sent, an email draft to `support@mivuapp.com` opens instead; without an
  email app the dialog offers "Copy address" and "Share"
  (`CoachReplyActionsTest`, `CoachReportsTest`).
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
- **Short description (80):** Log meals by photo or voice. No Mivu account; your diary is kept on your phone.
- **Category:** Health & Fitness (**owner to confirm**; Food & Drink is the
  alternative).
- **Contact email:** support@mivuapp.com (**Owner:** create the mailbox).
- **Privacy policy URL:** https://mivuapp.com/privacy/android (**Owner:**
  deploy it from `mivu-site`; it adds one page and changes no existing one).
  It covers the on-device Coach, ML Kit's Google diagnostics, reply reports
  and the 18+ age (**owner to confirm** the wording).
- **App icon (512 × 512):** `design-system/mivu/precision-glass/icon/android/play-icon-512.png`.
- **Feature graphic (1024 × 500):** `docs/verification/android-play/listing/feature-graphic.png` (Pip, the name and
  the App Store subtitle; rendered from HTML with headless Chrome).

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
> • A home-screen widget shows calories eaten against your target, with Snap It
>   and Coach one tap away.
> • Log from the app icon's shortcuts, a Quick Settings tile, or by sharing a
>   photo or text into Mivu.
>
> MEET PIP
> Pip, Mivu's fox companion, sets up your daily targets in about a minute and
> reacts as you log. Pip respects the system's Remove animations setting.
>
> PRIVATE BY DESIGN
> • No Mivu account. Your diary and photos are stored on your phone.
> • No ads, and no analytics or tracking of our own.
> • Export your diary and photos to a file at any time.
>
> AI THAT USES YOUR OWN PLAN
> Connect your ChatGPT account to estimate nutrition and chat with Coach.
> Coach needs an eligible ChatGPT plan; requests use it, and you can manage
> usage or disconnect in Settings. Mivu asks before anything is shared with OpenAI.
>
> On supported phones you can choose Gemini Nano on the phone instead of
> ChatGPT. It needs no account, but it only logs meals and changes amounts,
> with lower accuracy. Adding meals by hand works without either.
>
> Nutrition figures are estimates, not medical advice. Mivu is not a medical
> device and does not diagnose, treat, cure, or prevent any medical condition.
> Consult a healthcare professional for medical advice, diagnosis, or
> treatment.
>
> Mivu is an independent app and is not affiliated with or endorsed by OpenAI
> or Google. ChatGPT is a trademark of OpenAI, and Gemini is a trademark of
> Google.

**Owner:** the Gemini Nano paragraph describes a feature tested only with a
fake model so far (the Pixel 8 Pro and the emulator report it unavailable). Keep
it once the on-device Coach has been seen working on a supported phone;
otherwise delete it and its mention in the last line.

**Release notes (500):** First release.

## Screenshots

Phone screenshots at 1080 × 2160 (Play: 2 to 8 images, each side 320 to 3840 px,
the long side at most twice the short one, so the emulator's native 1080 × 2400 is
too tall). Taken on the emulator (`wm size 1080x2160`, demo-mode status bar at
9:41) with synthetic data: two weeks of meals and weights under a 2,000 kcal goal,
seeded by `ListingFixtureSeed` (`-e seedListing true`; the Coach shot adds
`-e holdCoachSeconds N`, which shows the app with a connected-looking Coach and
no sign-in). Files in
[`docs/verification/android-play/listing/`](../verification/android-play/listing/):

1. `play-01-today.png` — Your day at a glance (Today with Pip and meals)
2. `play-02-coach.png` — Log a meal in your own words (Saved food receipt and Pip's reply)
3. `play-03-progress.png` — See how close you land (Progress week with Pip)
4. `play-04-diary.png` — Every day, kept on your phone (Diary week)
5. `play-05-widgets.png` — Calories on your home screen (both widget sizes).
   **Do not upload as is:** it shows other apps' icons and the Google search bar. Retake it on a home
   screen that holds only Mivu's widgets, or leave it out; Play needs two screenshots and the other five qualify.
6. `play-06-setup.png` — Pip sets your targets in about a minute (Setup)

Shots 2 and 6 show "ChatGPT" as it appears in the app; the description's
non-affiliation line covers that use. They are raw captures; framing with brand teal and captions is the owner's
choice. A photo-capture shot is not included: it needs a real meal photo the
owner has rights to. The earlier 1080 × 1920 captures in `android-play/` are
superseded.

## Data safety (draft answers)

**Owner ruling (2026-10-25): declare the data sent to OpenAI as shared.** The
user-initiated-transfer exception was considered and not taken.

How the app works, from the code:
- The diary (meals, photos, weights, workouts, goals, profile, Coach chat) is
  stored only on the phone, in the app's private storage. There is no Mivu
  server for the diary and no Mivu account; the only Mivu service is the
  reply-reports worker described below.
- When the person connects ChatGPT and uses Coach, Mivu sends the turn's text
  and photos plus bounded diary context (profile, recent meals, weights,
  workouts, goal, recent Coach exchanges) to `api.openai.com` with the person's
  own ChatGPT token (`CoachContext.kt`, `ResponsesClient.kt`). Requests set
  `store: false`.
- Sign-in sends a random per-install host ID (`ext_agent_host_id`, a UUID) to
  `auth.openai.com` (`CredentialStore.hostID`, `OAuthAttempt.kt`).
- All network traffic is HTTPS. The only `http://` address is the sign-in
  callback on `127.0.0.1`, which never leaves the phone.
- With Gemini Nano chosen, Coach turns run on the phone and meals stay on the
  phone.
- Google's ML Kit GenAI SDK (`genai-prompt`) runs for every user, not only with
  Gemini Nano chosen: its init provider starts with the app, and Mivu asks it
  whether Gemini Nano is available at each launch and return
  (`MivuApplication.kt`, `MainActivity.onStart`). Google's
  [ML Kit data disclosure](https://developers.google.com/ml-kit/android-data-disclosure)
  (read 2026-11-11) says GenAI features collect device information, the app's
  package name and version, "user, device or other identifiers", per-install
  identifiers, performance metrics, input and output size, event types,
  error codes and the configured languages, for diagnostics and usage
  analytics. Meals and messages are not
  in that list.
- No analytics, crash reporting, advertising or location SDK of Mivu's own; no
  advertising ID.

**Overview questions**

| Question | Draft answer |
|---|---|
| Does your app collect or share any of the required user data types? | Yes |
| Is all of the user data collected by your app encrypted in transit? | Yes (HTTPS only) |
| Do you provide a way for users to request that their data is deleted? | Yes: in-app deletion of each meal, photo, weight and workout; Disconnect ChatGPT; Android's Clear storage or uninstall erases everything. Mivu holds no copy elsewhere, except Coach reply reports the person chose to send, which sit in Mivu's support inbox and are deleted on request to support@mivuapp.com. **Owner to confirm** how to describe data already sent to OpenAI under the person's ChatGPT account. |
| Account creation | The app does not let users create an account. ChatGPT sign-in is OpenAI's account, so account deletion does not apply. |

**Data types** — each, except the ML Kit row, is collected and shared with
OpenAI, only when the person uses Coach with ChatGPT connected; optional (the diary works without it); for
App functionality; not used for tracking, ads, analytics or personalization by
Mivu.

| Play data type | What Mivu sends | Collected | Shared | Ephemeral | Required |
|---|---|---|---|---|---|
| Photos and videos › Photos | Meal photos attached to a Coach turn | Yes | Yes | No (**owner to confirm**: `store: false`, but OpenAI's retention applies) | Optional |
| Health and fitness › Health info | Weight entries, height, pace, calorie and macro goals, the calories and macros of logged meals, diet tags and the free-text allergy, intolerance or health notes | Yes | Yes | No (as above) | Optional |
| Personal info › Other info | Birth year and sex from the profile (**owner to confirm** against the live form; they may belong under Health info instead) | Yes | Yes | No (as above) | Optional |
| Health and fitness › Fitness info | Logged workouts (kind, minutes) | Yes | Yes | No (as above) | Optional |
| App activity › Other user-generated content | Coach messages and meal names and notes | Yes | Yes | No (as above) | Optional |
| Personal info › Name | The profile name, part of the profile in the Coach context (**owner to confirm**: it is often a nickname, but it is sent) | Yes | Yes | No (as above) | Optional |
| Device or other IDs | The random per-install `ext_agent_host_id` sent at sign-in (**owner to confirm** whether Play counts it) | Yes | Yes | No | Optional |
| App info and performance › Diagnostics, and Device or other IDs (ML Kit) | Device information, app name and version, device and per-install identifiers, performance metrics, event types, error codes and configured languages that Google's ML Kit collects whenever the app runs, for every user. Purpose: Analytics (Google states diagnostics and usage analytics only). Not shared by Mivu (**owner to confirm** the exact rows against Google's ML Kit disclosure and the live form) | Yes | No | No | Required |

**Not collected:** location, contacts, financial info, calendar, files and docs,
web browsing, app interactions, crash logs, advertising ID. Mivu itself collects
no diagnostics; ML Kit's are in the row above and apply to every user.

**Voice input** uses Android's system speech recognizer; Mivu receives only the
transcribed text, which then goes into the message like typed text. The audio
is handled by the phone's speech service, which may process it on its
provider's servers (on most phones, Google); Mivu never receives or stores
audio. **Owner to confirm**
that Audio › Voice or sound recordings is "not collected".

**Coach reply reports**: when the person reports a reply, its text, the
reason, their note and the app version go to Mivu's own inbox through the
reports worker (Cloudflare, a service provider). Declare App activity › Other
user-generated content as collected, not shared, optional, for App
functionality (**owner to confirm** the purpose against the live form). A
reported reply can mention the person's meals, calories or weight, so also
mark Health and fitness › Health info as collected, not shared, optional, for
this feature. The email fallback is sent by the person, from their own email
app.

## Health apps declaration (draft)

- Features: nutrition and calorie tracking; weight management; activity
  (workout) logging.
- Not a medical device; no diagnosis, treatment or medical claims.
- Disclaimers in the app: "estimates, not medical advice" in Settings, on the
  onboarding targets step and in the empty Coach. Onboarding keeps weight-loss
  targets to a healthy BMI (not below 18.5), at most 0.75 kg a week, and never
  below 1200 kcal; minimum age 18. Those limits apply to the targets setup
  proposes; a person can later edit their own goal to any value, by hand or
  by asking Coach.
- No Health Connect access and no sensor, activity or location permissions. The camera (meal photos) and
  the microphone (voice logging through the system speech recognizer) are used only to log meals.

## AI-generated content (draft)

- Coach replies are generated by OpenAI models through the person's own
  ChatGPT account. The owner ruled the AI-generated content policy applies.
- In-app reporting: long-press a Pip reply (or use the TalkBack action) ›
  "Report reply" › reason and optional note › Report. The report is saved on the
  phone and sent to Mivu without leaving the app, as the policy requires; an
  email draft is only the fallback when sending fails. **Owner:** apply the
  reports worker in mivu-infra and read the inbox before release.
- Coach's instructions treat user text and retrieved content as data, keep
  replies short, and never state numbers it did not read.
- Restricted content: Coach's instructions tell it never to produce sexual,
  violent, hateful or self-harm content and to decline such requests
  (`CoachEngine.STABLE_RULES`, `CoachRestrictedContentTest`; Android only until
  the iPhone review is over). Coach can only call Mivu's food-diary tools and
  replies in a couple of short sentences. Beyond that rule Mivu adds no filter
  of its own and relies on the safeguards built into OpenAI's models; the
  on-device model only extracts foods as structured data, and Mivu words that
  reply itself (`OnDeviceInference.kt`). Reports are how a
  bad reply reaches the developer.

## Account deletion

Not applicable: Mivu creates no account. The diary is local; ChatGPT sign-in is
OpenAI's account. Data deletion: Settings › Coach AI › Disconnect ChatGPT
(deletes the stored tokens and revokes them), per-item delete in the app, and
Android Settings › Apps › Mivu › Storage › Clear storage (or uninstall). Owner
to confirm in the Console. OpenAI's sign-in page also offers sign-up, so if
the Console asks for a deletion link, give
`https://mivuapp.com/privacy/android#deleting`.

## App access (reviewer instructions, draft)

> Mivu is a private food diary. Diary data is stored only on this phone. Meal
> entry, editing, history, progress, widgets, export and reports work without
> any account.
>
> On first launch Pip's setup opens; finish it or tap Later. If you enter a
> birth year, use one at least 18 years back.
>
> Coach uses the person's own ChatGPT account. To test it: Settings › Coach AI ›
> Connect ChatGPT › Agree and Continue, then sign in to ChatGPT in the browser
> tab with the test account below. OpenAI then shows a page asking to let
> "Mivu" use the account; tap Continue. The browser returns to Mivu by itself;
> if it does not, tap "Return to Mivu". Coach AI now shows "ChatGPT connected". Open the
> Coach tab and send "two boiled eggs and a slice of toast"; Pip saves the meal
> and replies.
>
> To report an AI reply: long-press Pip's reply › Report reply › pick a reason ›
> Report. It is sent without leaving the app.
>
> Test ChatGPT account: `<email>` / `<password>`

In Console choose "All or some functionality is restricted" and add these
instructions with the account.

**Owner:** Phase 0 item 6 is still blocked. The account must be on a paid
ChatGPT plan and sign in from any country without a one-time code the reviewer
cannot receive; the owner must authorize it. The last recorded emulator sign-in
after the return-to-Mivu change ended in "Can't reach ChatGPT"
([record](../verification/2026-10-29-android-gemini-nano.md), cause not
found), so prove sign-in on the physical phone (check P1) before entering this.

## Other Console forms (draft)

- **Content rating (IARC):** reference app / utility; no violence, sexuality,
  profanity, drugs or gambling; users do not interact with each other; no
  location sharing; generated text from an AI chatbot (answer the AI question
  "yes"). **Owner to confirm** the rating the questionnaire returns.
- **Target audience:** 18 and over (owner ruling 2026-11-02: 18+ on Android,
  13+ on iOS). The [ML Kit GenAI terms](https://developers.google.com/ml-kit/genai-terms)
  bar apps "directed towards or likely to be accessed by individuals under the
  age of 18". Android onboarding refuses birth years under 18 and says "Mivu is
  for ages 18 and up" (`OnboardingScreenTest.underEighteenCannotContinue`).
  The gate covers setup only: a diary archive restored from another phone
  keeps its profile, including one made on iPhone by someone aged 13 to 17
  (**owner to decide** whether restore should check the birth year). The same
  terms ask the developer to tell users that Google processes ML Kit's
  metrics; today that is said in the Android privacy policy only (**owner to
  decide** whether to add a line in Settings › Coach AI).
  Pip, the cartoon fox, is a mascot for adults tracking calories and weight;
  nothing in the listing is addressed to children. Keep that answer ready if
  review asks about the artwork.
- **Ads:** no ads.
- **News app:** no. **Government app:** no. **Financial features:** none.
- **COVID-19 / health research:** no.
- **Advertising ID:** no. The merged release manifest has no
  `com.google.android.gms.permission.AD_ID`.
- **Package registration:** register `com.yakov103.mivu` in Console for Android
  developer verification.
- **Trader status:** **owner to confirm** against the Console page. Who must
  declare it, and for which regions, was not verified here.
- **Countries:** Israel and the United States must be included. Leave out
  China and countries under United States sanctions. Europe comes later, so
  nothing here is adapted for it yet.

## Closed test

- If the owner's developer account is a personal one created after
  13 November 2023, Play requires a closed test with at least 12 testers opted
  in for 14 continuous days before production. Testers only need Google
  accounts that opt in.
- The test starts only after Phase 0 items 2–5 pass on the physical phone (the
  [milestone 9 record](../verification/2026-10-25-android-play-readiness.md),
  "Physical phone").
- Testers need their own ChatGPT accounts for Coach; the rest of the app works
  without one.
- Applying for production is the owner's decision after the 14 days.

## Release steps (Owner)

0. `git checkout android-v<version>` (the tag of the version PR you merged),
   with a clean tree, and note `git rev-parse HEAD` for the ledger line in
   step 5.
1. Create the upload keystore
   (`keytool -genkeypair -v -keystore <absolute path> -alias <alias> -keyalg RSA -keysize 2048 -validity 10000`;
   check the key requirements on Play's app signing page first), keep it and its passwords outside
   the repo, and set `MIVU_UPLOAD_STORE_FILE` (absolute path),
   `MIVU_UPLOAD_STORE_PASSWORD`, `MIVU_UPLOAD_KEY_ALIAS` and
   `MIVU_UPLOAD_KEY_PASSWORD` in `~/.gradle/gradle.properties`.
2. `cd android && ./gradlew :app:bundleRelease`. Without the four values the
   bundle is built unsigned, so check it before going on:
   `jarsigner -verify app/build/outputs/bundle/release/app-release.aab` must
   say "jar verified", and
   `bundletool dump config --bundle=app/build/outputs/bundle/release/app-release.aab | grep -i alignment`
   must show `PAGE_ALIGNMENT_16K`. The permission and 16 KB facts in this
   draft came from an earlier local build, so repeat them on this bundle:
   `bundletool build-apks --mode=universal`, unzip the APK, then
   `apkanalyzer manifest print` (same permissions as "Done in the app" and
   the Health section, targetSdk 37) and `zipalign -c -P 16 4` on it.
3. Install the same AAB on the phone with bundletool
   (`build-apks --connected-device`, then `install-apks`) and run the release
   checks in the record's "Physical phone" section.
4. Upload the AAB to the internal or closed track in Play Console, and enroll
   in Play App Signing.
5. Add the ledger line `code name sha date track` to `android/play-uploads.txt`,
   run `python3 scripts/ci/play_ledger.py android/play-uploads.txt`, and commit
   it.
6. Read the pre-launch report.

## Later

- From April 2027 Play expects sign-in to be restored on a new phone. Mivu
  keeps ChatGPT credentials out of backups and transfers on purpose, so before
  then either adopt the Restore Credentials API or ask for an exemption in
  Console.
- The app targets API 37 and receives the sign-in redirect on `127.0.0.1`
  without a local-network permission. Check P1 on an Android 17 phone settles
  whether that works; Play's Local Network declaration (from 25 August 2027)
  applies only if the permission is ever added.
- Notifications are asked for when the morning reminder is turned on, and once
  after the first message shared into Mivu is saved.
