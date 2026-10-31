# Android Play Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Android build ready for the Google Play closed test
(milestone 9, the last one before it):
- a release AAB the owner can sign locally, with the ledger version code;
- proof that the R8-minified release still decodes archives, draws the
  widget, opens the share sheet and ships no debug code;
- Pip's launcher icon and a monochrome Pip notification icon;
- lint before push, so an Android 13-only call cannot break Android 12 again;
- the carried Coach polish and the known flaky tests;
- "Report a Coach reply", if the owner confirms the AI-content policy applies;
- the Play submission draft, and a checklist of everything only the owner
  can do.

**Architecture:** This is milestone 9. The app is feature-complete for the
closed test; this milestone changes the build and adds checks, not features.
- **Build.** `android/app/build.gradle.kts` gains an `upload` signing config
  read from Gradle properties or environment variables. The keystore never
  enters the repo. The version code already comes from
  `android/play-uploads.txt` (`nextVersionCode`), checked by
  `scripts/ci/play_ledger.py`.
- **Release smoke.** One property, `-Pmivu.testBuildType=release`, points the
  instrumented tests at the minified release build, signed with the debug
  key for that run only. A single `ReleaseSmokeTest` class runs there.
  Play rejects debug-signed uploads, so that build can never ship.
- **Push gate.** `scripts/ci/git_hooks.py` `android_check` adds
  `:app:lintDebug`. `NewApi` is a lint error by default, so an unguarded
  API 33 call fails the push.
- **Owner work** stays out of the tasks. It is the checklist at the end.
  No task accepts terms, signs with the owner's key, uploads or publishes.

**Tech Stack:** Kotlin, Jetpack Compose and Material 3 (BOM `2026.09.00`,
material3 1.4.0), AGP 9.4.1 with R8, Android lint, adaptive icons
(`<adaptive-icon>` with `<monochrome>`, API 33 themed icons), `keytool` and
`jarsigner` from the JDK, `zipalign` from build-tools, Python `unittest` for
the hook. No new dependency.

**Spec:** [`docs/superpowers/specs/2026-10-23-android-app-design.md`](../specs/2026-10-23-android-app-design.md)
(sections "Release build", "Build, test and evidence", "Path to Google Play",
"Play policy requirements", "Backup and restore", "Risks and open gates").

The scope comes from:
- [`android-carried-items.md`](android-carried-items.md): every "Play
  readiness" item, and the physical-phone items under "Connection",
  "Milestone 8" and "Settings and day rollover";
- [Phase 0 record](../../verification/2026-10-23-android-phase0.md): items 1
  (eligibility) and 6 (reviewer access) are external blockers; items 2–5
  still need the physical phone;
- the [milestone 8 record](../../verification/2026-10-25-android-widgets-share-backup.md):
  the screenshots not taken, the 4–8 s archive read, and the flaky classes;
- [`docs/development/app-store-submission.md`](../../development/app-store-submission.md):
  the iOS submission draft, which the Play draft mirrors.

## Scope decisions

**Kept:**
- **Upload signing, local only.** The `upload` signing config reads four
  names, each from a Gradle property first and then the environment:
  `MIVU_UPLOAD_STORE_FILE`, `MIVU_UPLOAD_STORE_PASSWORD`,
  `MIVU_UPLOAD_KEY_ALIAS`, `MIVU_UPLOAD_KEY_PASSWORD`.
  - All four set: `release` signs with them.
  - None set: `release` builds unsigned (the owner signs later, or sets the
    properties in `~/.gradle/gradle.properties`).
  - Some set: the build fails with "Upload signing needs all of
    MIVU_UPLOAD_STORE_FILE, MIVU_UPLOAD_STORE_PASSWORD, MIVU_UPLOAD_KEY_ALIAS,
    MIVU_UPLOAD_KEY_PASSWORD." A half-configured key must not silently
    produce an unsigned AAB.
  - `*.jks` and `*.keystore` are already in `.gitignore`.
- **Release smoke under R8** (carried: "release-minify smoke test", "the
  widget and the share activity survive R8"). It decodes the archive
  fixtures, draws the widget, opens the share sheet, checks the merged
  release components, and times the archive read.
- **R8 keep rules: none expected.** kotlinx.serialization 1.12.0 ships its own
  R8 rules, and the compiler plugin generates serializers without
  reflection. `SwiftEnumSerializer` uses class literals, not names. Manifest
  components (widget provider, share activity, tile, job service, receiver)
  are kept by AAPT's generated rules. `proguard-rules.pro` is created only if
  a smoke test fails, with one rule per failing class and a comment naming
  the test.
- **Launcher icon and notification icon.** An adaptive icon from the iOS
  default `AppIcon.png`, with a themed monochrome layer. The same monochrome
  Pip is the small icon of the Coach reply and morning notifications.
- **Lint before push.** `:app:lintDebug` joins the Android pre-push check.
  The last full run had 0 errors, so this adds no false failures today.
- **Coach polish** (carried): the meal chip's empty leading area, and
  "Choose photos" under the shutter at font scale 2.0.
- **Flaky tests** (carried): `CoachHistoryScreenTest.mealAskPipSeeksSourceTurn`,
  `MealEditorsTest.scaleToTargetUpdatesFoods` (the "EditorsTest flake"),
  `CoachCameraTest.recreateMidCaptureKeepsDraft` and
  `MorningReminderReceiverTest.alarmPostsTheMorningNotification`.
- **Report a Coach reply**, gated (see Task 5).
- **The Play submission draft** `docs/development/play-submission.md`: Data
  safety, health declaration, AI content, account deletion, privacy policy,
  app access, content rating, target audience, closed test. The spec asks
  for these "prepared in the repo. The owner submits."
- **Screenshots** not taken in milestone 8: `widget-no-target`,
  `launcher-shortcuts`, `qs-tile`, `share-chooser`, plus the new launcher
  icon and themed icon.

**Decided, each with its reason:**
- **Keep Android 12 (minSdk 31).** apilevels.com (Android Studio
  distribution data, read 2026-10-25) gives 78.8 % of devices at API 31+ and
  68.9 % at API 33+, so Android 12 and 12L are about 9.9 %. That is far above
  the 3 % threshold. The lint push gate protects it from now on.
- **Target API stays 37.** Play requires API 36 for new apps from
  31 August 2026; 37 satisfies it.
- **Material 3 Expressive stays deferred.** The pinned BOM `2026.09.00` is the
  newest BOM and maps to material3 1.4.0, the newest stable release
  (1.5.0 is at beta02 on 2026-10-25). `MaterialExpressiveTheme` and the
  Expressive `LoadingIndicator` stay internal there, and alphas and betas are
  not taken. Both move to "Later" with the BOM that first ships them stable
  as the trigger. The `shortcut:` comment in `CoachTimeline.kt` stays.
- **Backup rules already match the owner's decision** ("device transfer only,
  no Google cloud backup"). `allowBackup="true"` is correct: on apps
  targeting API 31+, `false` would not stop device transfer anyway, and the
  rules file is what decides. `data_extraction_rules.xml` excludes every
  domain from `<cloud-backup>` and `<cross-platform-transfer>`, and
  `<device-transfer>` includes only `database` and `file`. Credentials and
  `ext_agent_host_id` live in `noBackupFilesDir/accounts` (always excluded);
  the `chatgpt` and `mivu` preferences are not included anywhere. Task 3
  pins this with a unit test, so a later edit cannot drift.
- **Debug code is already out of release.** `ConnectionProofActivity`,
  `CaptureProbeActivity` and `PipRigPreviewActivity` live in `src/debug`;
  `src/release/SampleMode.kt` is a constant `false`; the screenshot seeds
  live in `androidTest`. `coachInferenceForTest` is a null test seam in
  `MivuApplication`, not debug code, and stays. Task 3 checks the installed
  release package.
- **16 KB pages are relevant.** CameraX ships native libraries. Task 3 runs
  `zipalign -c -P 16` on the release APK; a failure is fixed by the CameraX
  version, not by build flags.
- **Account deletion is not applicable.** Mivu creates no account: the
  diary is local and ChatGPT sign-in is OpenAI's account. The draft says so
  and points the data-deletion answer at the in-app Disconnect and Android's
  "Clear storage". The owner confirms it in the Console.
- **Archive export memory stays as it is** (carried: about 100 MB of Java
  heap at 120 MB of photos). The 120 MB test passes within the emulator's
  192 MB heap, and real diaries are far smaller. It moves to "Later" with
  the trigger "a physical phone fails the 120 MB export".
- **Release builds are verified on the emulator here.** Physical-phone
  checks are owner items (below); emulator evidence never replaces them.

**Deferred or cut:**
- Store listing text and phone screenshots for the listing: these follow the
  owner's account and category answers. The draft lists what is needed.
- The Settings rows (profiles, diary preferences, nutrition source) and the
  Responses-host offline mapping: not Play gates; they stay carried.
- Uploading, the ledger line for a real upload, and anything in Play Console:
  owner only.

## Global Constraints

- **Paths:** `A/` = `android/app/src/main/java/com/yakov103/mivu/`, `T/` =
  `android/app/src/test/java/com/yakov103/mivu/`, `I/` =
  `android/app/src/androidTest/java/com/yakov103/mivu/`, `R/` =
  `android/app/src/main/res/`.
- **Platform:** minSdk 31, targetSdk 37, compileSdk 37; no new dependency, no
  new permission, no schema change; the archive stays `mivu-diary` v4.
- **Secrets:** no keystore, password or key alias in the repo, in logs, in a
  commit message or in a verification record. Signing checks use a throwaway
  keystore created in the session scratch folder with synthetic values, and
  delete it afterwards.
- **Owner boundary:** no task accepts terms, creates a Play account, uploads,
  signs with the owner's key, enters Console answers, or publishes. The
  draft is labelled a draft.
- **Synthetic data only:** archive fixtures from `fixtures/archive/`,
  `TodayFixture` and `DiaryFixture` diaries, generated photo bytes; no live
  ChatGPT call (`coachInferenceForTest`).
- **Accessibility:** 48 dp targets; the Report action is also a TalkBack
  custom action; the launcher icon has the label "Mivu"; the notification
  icon is decorative.
- **Copy** (fixed here):
  - Report: menu item "Report"; dialog title "Report this reply?"; message
    "Mivu opens your email app with this reply so you can send it to us.
    Nothing else from your diary is included."; buttons "Report" and
    "Cancel"; email subject "Mivu Coach reply report".
  - Signing error: the "Upload signing needs all of …" line above.
- **Speed:** each task runs only its own test classes, one class per
  `connectedDebugAndroidTest` run. The full suite and the release smoke run
  once, in Task 6. Batch review 1 after Task 2, batch review 2 after Task 4,
  final review after Task 6.

  ```sh
  cd android
  ./gradlew :app:testDebugUnitTest --tests '*<Class>'
  ./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.yakov103.mivu.<pkg>.<Class>
  ./gradlew :app:connectedReleaseAndroidTest -Pmivu.testBuildType=release -Pandroid.testInstrumentationRunnerArguments.class=com.yakov103.mivu.release.ReleaseSmokeTest
  ```

## Review Focus

1. **Three of the four signing values set** (a typo in
   `~/.gradle/gradle.properties`). The build fails with the "Upload signing
   needs all of …" line; it never writes an unsigned AAB that looks ready.
   (Task 1: Step 4, `partial signing properties fail the build`)
2. **An API 33-only call added without a version check.** `git push` stops at
   `:app:lintDebug` with `NewApi`, before any upload.
   (Task 1: `test_android_check_runs_units_and_lint`)
3. **An archive restored on the minified release build.** Both the Android
   and the iOS v4 fixtures decode to the same profile and meal counts as on
   debug; R8 has not stripped a serializer.
   (Task 3: `androidAndIosFixturesDecode`)
4. **A release build that still exposes the proof screen or sample mode.**
   The installed release package lists none of the three debug activities,
   only one launcher activity, and `SampleMode.enabled` is false.
   (Task 3: `releaseShipsNoDebugComponents`)
5. **A rules edit that lets the diary reach Google cloud backup.** The unit
   test fails unless `<cloud-backup>` excludes every domain and
   `<device-transfer>` includes only `database` and `file`.
   (Task 3: `BackupRulesTest.cloudExcludesEverythingAndTransferKeepsTheDiary`)

---

### Task 1: Upload signing and lint before push

**Files:**
- Modify:
  - `android/app/build.gradle.kts` (`signingConfigs.upload`, the release
    `signingConfig`);
  - `scripts/ci/git_hooks.py` (`android_check`);
  - `scripts/ci/test_git_hooks.py`
    (`test_android_units_run_only_when_android_changes` becomes
    `test_android_check_runs_units_and_lint`);
  - `docs/development/ci-cd.md` (one line: Android pushes run unit tests and
    lint).

**Interfaces:**
- Produces:
  - Gradle/env names `MIVU_UPLOAD_STORE_FILE`, `MIVU_UPLOAD_STORE_PASSWORD`,
    `MIVU_UPLOAD_KEY_ALIAS`, `MIVU_UPLOAD_KEY_PASSWORD`;
  - `fun uploadSetting(name: String): String?` in `build.gradle.kts`:
    `providers.gradleProperty(name).orElse(providers.environmentVariable(name)).orNull`;
  - `android_check(head)` runs `./gradlew :app:testDebugUnitTest :app:lintDebug`.

- [ ] **Step 1: Failing test.** Rename and change the hook test so the fake
  `gradlew` log must read
  `f'{root}/android :app:testDebugUnitTest :app:lintDebug\n'`.
- [ ] **Step 2: Run**
  `python3 -m unittest scripts/ci/test_git_hooks.py -k android`. Expected:
  FAIL (log lacks `:app:lintDebug`).
- [ ] **Step 3: Implement** `android_check` with both tasks in one Gradle
  call, and the signing config:
  - all four values set: `signingConfigs.create("upload")` from them, and
    `release { signingConfig = upload }`;
  - none set: no signing config on `release`;
  - some set: `error("Upload signing needs all of …")` at configuration time.
- [ ] **Step 4: Verify signing** with a throwaway keystore:

  ```sh
  S=<session scratch>/sign && mkdir -p "$S"
  keytool -genkeypair -keystore "$S/t.jks" -alias t -keyalg RSA -keysize 2048 -validity 1 \
    -storepass synthetic1 -keypass synthetic1 -dname "CN=Mivu Test"
  cd android
  ./gradlew :app:bundleRelease -PMIVU_UPLOAD_STORE_FILE="$S/t.jks" -PMIVU_UPLOAD_STORE_PASSWORD=synthetic1 \
    -PMIVU_UPLOAD_KEY_ALIAS=t -PMIVU_UPLOAD_KEY_PASSWORD=synthetic1
  jarsigner -verify -verbose -certs app/build/outputs/bundle/release/app-release.aab | grep -c "CN=Mivu Test"
  ./gradlew :app:bundleRelease && jarsigner -verify app/build/outputs/bundle/release/app-release.aab
  ./gradlew :app:bundleRelease -PMIVU_UPLOAD_STORE_FILE="$S/t.jks"
  rm -rf "$S"
  ```

  Expected: the first build is signed by "CN=Mivu Test" (count > 0); the
  second prints "jar is unsigned."; the third (`partial signing properties
  fail the build`) fails with the "Upload signing needs all of …" line. Then
  `git ls-files '*.jks' '*.keystore'` prints nothing.
- [ ] **Step 5: Run** the hook tests and `./gradlew :app:lintDebug`.
  Expected: PASS; lint 0 errors.
- [ ] **Step 6: Commit**

```bash
git add android/app/build.gradle.kts scripts/ci/git_hooks.py scripts/ci/test_git_hooks.py docs/development/ci-cd.md
git commit -m "build(android): sign release uploads locally and lint before push"
```

### Task 2: Pip launcher icon and notification icon

**Files:**
- Create:
  - `R/mipmap-anydpi/ic_launcher.xml` (`<adaptive-icon>`: background
    `@color/ic_launcher_background`, foreground `@drawable/ic_launcher_foreground`,
    monochrome `@drawable/ic_launcher_monochrome`);
  - `R/drawable-nodpi/ic_launcher_art.png`: `ios/Mivu/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
    resized to 432 × 432 with `sips -Z 432` (the provenance line names both);
  - `R/drawable/ic_launcher_foreground.xml`: an `<inset>` of the art by
    `16.667%`, so the whole portrait sits in the 72 dp safe zone;
  - `R/drawable/ic_stat_pip.xml`: a 24 dp single-colour vector of Pip's head
    and ears, traced from the `head@front`, `ear-l@front` and `ear-r@front`
    paths in `design-system/mivu/characters/pip/rig/pip.svg` (filled
    outlines only, no inner detail);
  - `R/drawable/ic_launcher_monochrome.xml`: an `<inset>` of `ic_stat_pip` by
    `25%` (the themed-icon safe area);
  - `R/values/ic_launcher_background.xml`: the art's edge colour, sampled
    from the PNG's corner pixel.
- Modify:
  - `AndroidManifest.xml`: `android:icon="@mipmap/ic_launcher"` and
    `android:roundIcon="@mipmap/ic_launcher"`;
  - `A/coach/CoachReplyNotification.kt:64` and `A/day/MorningReminder.kt:68`:
    `setSmallIcon(R.drawable.ic_stat_pip)`.
- Test: `I/AppIconTest.kt`; one assertion added to
  `I/day/MorningReminderReceiverTest.kt` and `I/coach/CoachReplyFollowTest.kt`.

**Interfaces:**
- Produces: `R.mipmap.ic_launcher`, `R.drawable.ic_stat_pip`.

- [ ] **Step 1: Failing tests.**
  - `AppIconTest.launcherIconIsAdaptiveWithMonochrome`:
    `packageManager.getApplicationInfo(packageName, 0).icon != 0`, and
    `loadIcon` is an `AdaptiveIconDrawable` whose `monochrome` is not null
    (`assumeTrue(SDK_INT >= 33)` for the monochrome line only).
  - `AppIconTest.launcherActivityUsesTheIcon`: the `MAIN`/`LAUNCHER`
    `ResolveInfo.getIconResource() == R.mipmap.ic_launcher`.
  - In `alarmPostsTheMorningNotification` and
    `backgroundReplyPostsOnceAndOpensCoach`: the posted notification's
    `smallIcon.resId == R.drawable.ic_stat_pip`.
- [ ] **Step 2: Run** the three classes. Expected: FAIL (icon 0; small icon
  is `ic_notifications`).
- [ ] **Step 3: Implement** the files above.
- [ ] **Step 4: Run** the three classes and `./gradlew :app:lintDebug`.
  Expected: PASS; `MissingApplicationIcon` is gone.
- [ ] **Step 5: Look.** Screenshot the launcher (default and themed icons
  on), the app drawer, and a posted notification; save as
  `docs/verification/android-play/launcher-icon.png`,
  `launcher-icon-themed.png`, `notification-icon.png`. Check Pip's ears and
  scarf are not clipped by the circle mask, against the iOS icon.
- [ ] **Step 6: Commit**

```bash
git add android/app/src/main android/app/src/androidTest docs/verification/android-play
git commit -m "feat(android): add Pip's launcher and notification icons"
```

**Batch review 1** (Tasks 1–2) runs here.

### Task 3: Release smoke test under R8

**Files:**
- Modify: `android/app/build.gradle.kts`:
  - `testBuildType = providers.gradleProperty("mivu.testBuildType").getOrElse("debug")`;
  - when that property is `release` and no upload key is set,
    `release { signingConfig = signingConfigs.getByName("debug") }` (comment:
    for the on-device smoke only; Play rejects debug-signed uploads).
- Create:
  - `I/release/ReleaseSmokeTest.kt`;
  - `T/BackupRulesTest.kt`;
  - `android/app/proguard-rules.pro`, only if a smoke test fails under R8
    (then add it to `proguardFiles`).

**Interfaces:**
- Consumes: `DiaryArchive.decode(input, spool)`, `DiaryArchive.encode(snapshot, out)`,
  `PhotoSpool(dir)`, `CaloriesWidget.small/medium(context, snapshot, nowMillis)`,
  `WidgetSnapshot`, `ShareToCoachActivity`, `SampleMode.enabled`; fixtures
  `archive/android-v4-full.json` and `archive/ios-v4-full.json` (androidTest
  resources).
- Produces: the Gradle property `mivu.testBuildType` (default `debug`).

- [ ] **Step 1: Write the tests.** `ReleaseSmokeTest` uses only
  `androidx.test` and platform APIs (no Compose test rule, which is
  `debugImplementation`):
  - `androidAndIosFixturesDecode`: both fixtures decode through a
    `PhotoSpool` in `cacheDir`; the profile ID, meal count and photo count
    match the values the debug `ArchiveRoundTripTest.iosFixtureStillImports`
    asserts; re-encoding the Android fixture's snapshot gives the same JSON
    value as the file.
  - `archiveReadTime`: decodes `ios-v4-full.json` five times and reports the
    median milliseconds through `InstrumentationRegistry.getInstrumentation().sendStatus`
    (key `archiveReadMs`). It asserts nothing; the number goes in the record.
  - `widgetDrawsUnderR8`: `small` and `medium` with a synthetic snapshot
    (1,360 of 2,100 kcal) apply to a `FrameLayout` and show "1,360".
  - `shareSheetOpens`: `ActivityScenario.launch` of an `ACTION_SEND`
    `text/plain` intent ("two boiled eggs and a slice of toast") to
    `ShareToCoachActivity` reaches `RESUMED`; the scenario is closed without
    sending.
  - `releaseShipsNoDebugComponents`: `getPackageInfo(GET_ACTIVITIES)` names
    none of `ConnectionProofActivity`, `CaptureProbeActivity`,
    `PipRigPreviewActivity`; exactly one activity resolves `MAIN`/`LAUNCHER`;
    `SampleMode.enabled` is false; `ApplicationInfo.FLAG_DEBUGGABLE` is not
    set; `FLAG_ALLOW_BACKUP` is set.
  - `BackupRulesTest.cloudExcludesEverythingAndTransferKeepsTheDiary` (unit):
    parses `src/main/res/xml/data_extraction_rules.xml`; `<cloud-backup>` and
    `<cross-platform-transfer>` exclude all nine domains; `<device-transfer>`
    has exactly the includes `database` and `file` and no others.
- [ ] **Step 2: Run** `BackupRulesTest` and, on debug, `ReleaseSmokeTest`.
  Expected: PASS on debug (the tests are the guard, not new behaviour).
- [ ] **Step 3: Implement** the `testBuildType` switch, then run
  `ReleaseSmokeTest` with `-Pmivu.testBuildType=release`. Expected: PASS. If
  a test fails with a missing class or serializer, add the narrowest
  `-keep` rule to `proguard-rules.pro`, named after the test, and rerun.
- [ ] **Step 4: 16 KB and contents.** On `app-release.apk` from
  `./gradlew :app:assembleRelease -Pmivu.testBuildType=release`:
  `unzip -l … | grep '\.so$'` (record the list), then
  `"$ANDROID_HOME"/build-tools/<newest>/zipalign -c -P 16 -v 4 …`. Expected:
  "Verification successful". Also
  `unzip -l … | grep -ci 'ConnectionProof\|CaptureProbe\|PipRigPreview'`
  prints 0.
- [ ] **Step 5: Commit**

```bash
git add android/app/build.gradle.kts android/app/src/androidTest/java/com/yakov103/mivu/release android/app/src/test/java/com/yakov103/mivu/BackupRulesTest.kt
git commit -m "test(android): smoke-test the minified release build"
```

(Add `android/app/proguard-rules.pro` to the `git add` only if Step 3
created it.)

### Task 4: Coach polish and the flaky tests

**Files:**
- Modify:
  - `A/ui/coach/CoachTimeline.kt` (`CoachPhoto` with `id == null` draws
    `R.drawable.ic_restaurant` at 22 dp, centred, `onSurfaceVariant`, no
    content description);
  - `A/ui/coach/CoachCameraScreen.kt` (the bottom bar: at large font scales
    "Choose photos" goes on its own row below the shutter, and never
    overlaps it);
  - the flaky tests' classes, and app code only where a cause is found there.
- Test: `I/ui/coach/CoachScreenTest.kt`, `I/ui/coach/CoachCameraTest.kt`,
  `I/ui/coach/CoachHistoryScreenTest.kt`, `I/ui/meal/MealEditorsTest.kt`,
  `I/day/MorningReminderReceiverTest.kt`.

**Interfaces:** none new.

- [ ] **Step 1: Failing tests.**
  - `CoachScreenTest.mealChipWithoutPhotoShowsTheMealIcon`: a question
    about a meal with no photo shows the chip's icon node (test tag
    `coachPhotoPlaceholder`).
  - `CoachCameraTest.choosePhotosClearsTheShutterAtFontScale2`: at font scale
    2.0, the bounds of "Choose photos" and the shutter do not intersect, and
    both are at least 48 dp.
- [ ] **Step 2: Run** both. Expected: FAIL. **Implement**, run again.
  Expected: PASS.
- [ ] **Step 3: Flaky tests,** with superpowers:systematic-debugging, one
  class at a time. For each, find the cause before changing anything
  (a missing `waitUntil`, a shared diary, the clock, a real bug); fix the
  cause; record it in one line for Task 6. The class then passes three runs
  in a row. If no cause is found, record "not reproduced in N runs" and
  leave the test unchanged; never add retries or `@Ignore`.
  - `CoachHistoryScreenTest.mealAskPipSeeksSourceTurn` (already failing at
    `9987338b`);
  - `MealEditorsTest.scaleToTargetUpdatesFoods`;
  - `CoachCameraTest.recreateMidCaptureKeepsDraft`;
  - `MorningReminderReceiverTest.alarmPostsTheMorningNotification`.
- [ ] **Step 4: Check the two carried test items already closed by later
  commits:** `TodayScreenTest.logWithPipSelectsCoach` now waits (`a0541bc1`),
  and the seeds are excluded by annotation (`6fdce039`). Confirm from source
  and remove them in Task 6.
- [ ] **Step 5: Commit** (one commit per fixed cause is fine)

```bash
git add android/app/src/main/java/com/yakov103/mivu/ui/coach android/app/src/androidTest
git commit -m "fix(android): show the meal icon on Coach chips and keep Choose photos clear of the shutter"
```

**Batch review 2** (Tasks 3–4) runs here.

### Task 5: Report a Coach reply (gated)

**Gate:** start only after the owner answers checklist item 7 (the Coach is
in scope of the AI-generated content policy, and the report address). If the
owner rules it out of scope, skip this task, set the parity row
`report-coach-reply` Android `n/a` with the owner's reason in Task 6, and
record the reason in the submission draft.

**Files:**
- Modify:
  - `A/ui/settings/ChatGPTConnectButton.kt` (`MivuLinks.REPORT_EMAIL`, the
    owner's address);
  - `A/ui/coach/CoachTimeline.kt` (`MessageActions` gains an optional
    `onReport`; only assistant reply bubbles pass it);
  - `docs/parity.md` (`report-coach-reply`).
- Test: `I/ui/coach/CoachReplyActionsTest.kt`.

**Interfaces:**
- Consumes: `MessageActions(text, onReply, content)` and the existing
  long-press menu and TalkBack custom actions.
- Produces: `fun reportIntent(reply: String): Intent`, an `ACTION_SENDTO`
  `mailto:` intent to `MivuLinks.REPORT_EMAIL` with `EXTRA_SUBJECT`
  "Mivu Coach reply report" and `EXTRA_TEXT` the reply text only.

- [ ] **Step 1: Failing tests** in `CoachReplyActionsTest`, with
  Espresso-Intents:
  - `replyMenuOffersReport`: long-press on a Coach reply shows "Report"; a
    user message's menu does not.
  - `reportAsksThenOpensEmail`: "Report" shows the dialog copy from Global
    Constraints; "Report" fires one `ACTION_SENDTO` to the address with the
    subject and exactly the reply text; "Cancel" fires nothing.
  - `reportIsATalkBackAction`: the reply node has a "Report" custom action.
- [ ] **Step 2: Run.** Expected: FAIL. **Implement**, run again. Expected:
  PASS. If no app handles `mailto:`, show the address in the dialog with a
  "Copy address" button instead of failing silently.
- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu/ui android/app/src/androidTest/java/com/yakov103/mivu/ui/coach/CoachReplyActionsTest.kt docs/parity.md
git commit -m "feat(android): report a Coach reply by email"
```

### Task 6: Play submission draft, full suite, release smoke and record

**Files:**
- Create:
  - `docs/development/play-submission.md`;
  - `docs/verification/2026-10-25-android-play-readiness.md`;
  - `docs/verification/android-play/*.png`.
- Modify:
  - `docs/parity.md` (`store-readiness`, and `report-coach-reply` if Task 5
    ran or was ruled out);
  - `docs/superpowers/plans/android-carried-items.md`;
  - `README.md` or `docs/development/ci-cd.md` only to link the new draft.

**Interfaces:** consumes everything above.

- [ ] **Step 1: Write `play-submission.md`,** headed "A draft for the owner.
  Nothing here has been entered in Play Console, and no terms have been
  accepted." Sections, each with the source link the spec gives:
  - **Done in the app:** consent before ChatGPT, the privacy link
    (`MivuLinks.PRIVACY`), the "estimates, not medical advice" notes,
    backup rules, release without debug code, target API 37, minSdk 31 and
    why.
  - **Data safety (draft answers with reasoning):** meal photos, health info
    (weight, height, age, sex, goals), fitness info (workouts), other
    user-generated content (meal notes, Coach messages). Each is "collected"
    because it leaves the device to OpenAI when the person uses the Coach,
    "not shared" under the user-initiated-transfer exception, encrypted in
    transit, required only for Coach analysis, no tracking, no ads, no
    analytics. State plainly that the "sharing" reading is the owner's call.
  - **Health apps declaration:** nutrition and weight management; not a
    medical device; the in-app disclaimers.
  - **AI-generated content:** the Coach and the report path from Task 5, or
    the owner's out-of-scope reason.
  - **Account deletion:** not applicable, with the reason above; data
    deletion via Disconnect and "Clear storage".
  - **App access:** the reviewer path from Phase 0 item 6, with placeholders
    `<email>` / `<password>` only.
  - **Content rating, target audience (13+, as onboarding enforces), ads
    (none), news (no), government (no).**
  - **Closed test:** 12 testers opted in for 14 continuous days (personal
    accounts created after 13 November 2023); the test starts only after
    Phase 0 items 2–5 pass on the physical phone.
  - **Release steps for the owner:** set the four signing values, run
    `./gradlew :app:bundleRelease`, install the same AAB with bundletool on
    the phone and run the release checks, upload, then add the ledger line
    (`code name sha date track`), run `python3 scripts/ci/play_ledger.py
    android/play-uploads.txt`, and commit it.
- [ ] **Step 2: Full suite once** at a clean commit:

  ```sh
  cd android
  ./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleRelease --rerun-tasks --continue
  ./gradlew :app:connectedReleaseAndroidTest -Pmivu.testBuildType=release \
    -Pandroid.testInstrumentationRunnerArguments.class=com.yakov103.mivu.release.ReleaseSmokeTest
  ```

  Then `python3 scripts/ci/parity.py`, `python3 scripts/ci/play_ledger.py
  android/play-uploads.txt`, and `python3 -m unittest discover -s scripts/ci
  -p 'test_*.py' < /dev/null`. Record the SHA, emulator, API level and counts
  from the JUnit XML; never count a skipped or zero-test class; record each
  failure with its cause.
- [ ] **Step 3: Release measurements.** Record `archiveReadMs` from the
  release smoke next to the same test on debug, and the 16 KB result and
  native library list from Task 3. If the release read is still over 1 s for
  the 17 KB fixture, carry it with the number.
- [ ] **Step 4: Screenshots** (emulator, synthetic data, light, dark and
  font scale 2.0 where the surface supports it): `widget-no-target`,
  `launcher-shortcuts`, `qs-tile`, `share-chooser`, and the icons from
  Task 2. Compare each with the mockup or the iOS counterpart.
- [ ] **Step 5: Record** `2026-10-25-android-play-readiness.md` with the
  Decisions from this plan, the flaky-test causes from Task 4, and a
  **Physical phone** section listing every owner check below as `blocked`
  until run, each with the steps to run it.
- [ ] **Step 6: Parity and carried items.**
  - `store-readiness`: Android `partial` (draft and build ready; Console
    entries are the owner's).
  - Remove from carried items, each with its outcome: release-minify smoke
    (both lines), launcher and notification icon, `MaterialExpressiveTheme`
    (moved to Later), archive export memory (moved to Later), Coach meal
    chip, Coach camera at font 2.0, the flaky-test line (or what remains of
    it).
  - Move every physical-phone item into one "Physical phone (owner)" section
    that points at the record.
- [ ] **Step 7: Commit**

```bash
git add docs/development/play-submission.md docs/verification/2026-10-25-android-play-readiness.md docs/verification/android-play docs/parity.md docs/superpowers/plans/android-carried-items.md
git commit -m "docs(android): draft the Play submission and record milestone 9"
```

**Final review** of the whole milestone runs here.

---

## Owner checklist (not agent tasks)

No agent does any of these. Each one is done by the owner, in the owner's
own accounts, or with the owner's explicit go-ahead for that step.

1. **Play account type.** Ask Google Play support whether a nutrition
   tracker needs an organization account (D-U-N-S) or may use a personal one.
2. **Play Console account.** Create it, pay the fee, complete identity
   verification, and accept the Developer Distribution Agreement and any
   other terms.
3. **Upload key.** Create the upload keystore with `keytool`, keep it and its
   passwords outside the repo (a password manager plus an offline copy), set
   the four `MIVU_UPLOAD_*` values in `~/.gradle/gradle.properties`, and
   enroll in Play App Signing.
4. **OpenAI written answer** (Phase 0 item 1): whether a closed-source,
   Play-distributed Mivu may use ChatGPT sign-in and plan usage.
5. **Reviewer account** (Phase 0 item 6): authorize and create a dedicated
   ChatGPT plan account for Play review that signs in without a one-time code
   the reviewer cannot receive; enter it under App access.
6. **Privacy policy and support pages:** publish `https://mivuapp.com/privacy`
   (already linked in the app) and the support page; enter the URL in the
   Console.
7. **AI-generated content ruling:** decide whether the Coach is "central"
   under the policy, and the address that receives reports (unblocks Task 5).
8. **Console forms:** Data safety, health apps declaration, content rating,
   target audience, ads and the rest, using `play-submission.md` as the
   draft and checking each answer against the live form.
9. **Physical phone** (any Android 12+ phone; an Android 12 one also covers
   the API 31–32 clipboard toast). With the release AAB installed through
   bundletool:
   - Phase 0 items 2–5: sign-in, the Custom Tab return, a live text and
     photo Coach turn, leaving mid-turn, Disconnect (a new message saves as
     `waitingForConnection`), refresh;
   - Pip's frame rate, TalkBack across the tabs, live voice input;
   - keyboard on the non-Coach text screens (still `adjustPan`) and the
     composer gap;
   - the reply and morning notifications (delivery and tap), the widget's
     update after a capture and after 04:00;
   - the API 31–32 clipboard toast on Copy;
   - folder backup providers, and device-to-device restore if two phones are
     available.
10. **First upload:** build and sign the AAB locally, upload it to the
    internal or closed track, add and commit the ledger line, and read the
    pre-launch report.
11. **Closed test:** recruit at least 12 testers and keep them opted in for 14
    continuous days; then, only on the owner's decision, apply for
    production.
