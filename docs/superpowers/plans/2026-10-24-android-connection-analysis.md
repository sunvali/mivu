# Android ChatGPT Connection and Live Analysis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a person connect ChatGPT from the release app, and have meals
and Coach messages analyzed live, as on iOS. This adds the connection owner,
the Settings and Coach AI screens, OpenAI sharing consent, the model picker,
usage links, the Coach and meal connect/retry paths, background continuation,
and the live Phase 0 run through the real UI.

**Architecture:** This is milestone 5. A new `ChatGPTConnection` owns the one
`AuthSession` for the process. It is a small port of iOS `ChatGPTConnection`:
account state, consent, models, the selected model, notices, and a
`respond` call bound to the session revision. `MivuApplication` drops its
"has a registration" heuristic and its first-model shortcut and reads this
owner instead. The debug proof screen signs in through it too.

The UI is one shared `ChatGPTConnectButton` (consent dialog, then a Custom
Tab sign-in), used by the new Coach AI screen and by the Coach footnote.

Live meal analysis is the Coach, as on iOS: iOS `processPending` only ever
runs `SampleAnalyzer`, and live meals go through `CoachEngine`
(`DiaryViewModel.resumeWorker` hands off to `resumeCoach` outside sample
mode). So `MealAnalysisWorker` stays the sample-mode worker, and the live
path is the Coach worker that already exists, now with a real connection.

Background continuation uses a platform `JobScheduler` expedited job, the
Android analogue of iOS `continueInBackground`.

**Tech Stack:** Kotlin, Jetpack Compose (Material 3 `LargeTopAppBar`,
`AlertDialog`, `ExposedDropdownMenuBox`, `ListItem`), navigation-compose,
`androidx.browser` Custom Tabs (moved from `debugImplementation` to
`implementation`), platform `JobScheduler`/`JobService`, `SharedPreferences`,
JUnit with the existing `FakeAuthServer` and `HttpServer` fakes, Compose UI
instrumented tests. No new dependency.

**Spec:** [`docs/superpowers/specs/2026-10-23-android-app-design.md`](../specs/2026-10-23-android-app-design.md)
(the ChatGPT connection, OpenAI data consent and Coach capture rows; "Durable
capture and analysis"; "Phase 0"; "Play policy requirements"; "Background
analysis" in Settled details), and the mockup
[android-connection-mockup.png](../../verification/android-design/android-connection-mockup.png).
Carried items come from [`android-carried-items.md`](android-carried-items.md)
(Milestone 5, and "Wire the profile button, or hide it" from Play readiness),
and the M5 deferrals in the 4b and 4c ledgers
(`.superpowers/sdd/2026-10-24-android-coach-screens/progress.md`,
`.superpowers/sdd/2026-10-24-android-coach-history/progress.md`).

**iOS sources:**
- `ios/Mivu/Connection/ChatGPTConnection.swift` (states, `ConnectionNotice`
  copy, `restore`, `connect`, `loadModels`, `disconnect`, `apply`,
  `reflectFailure`, `pausePermission`, `respondForCoach`'s `validate`);
- `ChatGPTConnectButton.swift` (titles, consent first);
- `OpenAIConsent.swift` (consent copy, `MivuLinks`);
- `ios/Mivu/Diary/SettingsView.swift` lines 29–75 and 206–245 (the Settings
  rows and the "Connection" section);
- `ios/Mivu/Coach/CoachView.swift` lines 378–395 (footnote), 642–700 (turn
  status, Try again, `coachSettingsLink`);
- `ios/Mivu/Diary/TodayView.swift` lines 200–212 and 401–404 (plan welcome);
- `ios/Mivu/Coach/CoachViewModel.swift` `retryMeal` (555) and
  `continueInBackground` (575);
- `ios/Mivu/Diary/DiaryDatabaseScreenQueries.swift` `coachTurnForMeal` (35);
- `ios/Mivu/Diary/MealDetailView.swift` lines 130–136 and 311–321.

Copy is verbatim, with "iPhone" replaced by "phone".

## Scope decisions

**Kept:**
- the connection owner, with consent gating restore (iOS 73a939e5) and the
  plan-permission pause;
- Settings (opened by the profile button) with only the rows Android can back:
  "Coach AI", "Privacy Policy" and the estimates note. This settles the carried
  "Wire the profile button, or hide it" item;
- the Coach AI screen: connection state, Connect / Cancel connection,
  "Account model", "Disconnect ChatGPT", the notice, "Manage usage";
- the consent dialog before any sign-in;
- the composer footnote link, the connected footnote, and the receipt
  "Open ChatGPT connection" / "Open Settings" links;
- the one-time "You're using your ChatGPT plan" dialog (parity row
  `connection-plan-use`);
- "Retry analysis" on a meal outside sample mode (iOS `retryMeal`);
- background continuation through an expedited job;
- the live Phase 0 run through the release UI.

**Decided, each with its reason:**
- **Live meal analysis is the Coach.** iOS has no live meal analyzer outside
  `CoachEngine`, and Android's "Log meal" composer is sample-only, as on iOS.
  `MealAnalysisWorker` keeps `SampleAnalyzer`, a synchronous local function,
  so it makes no network call. The three carried worker items close:
  - "mutex across network calls": no network call happens under it;
  - "StaleRevision retries cost 3 paid calls": the retries are local and free.
    The live Coach path already retries a transient failure at most three times
    (iOS `resilient`), and a stale write is not retried as a paid call
    (`CoachEngine` saves `needsRetry`);
  - "failures swallowed": a failed sample analysis already marks the meal
    `needsRetry`, so the meal row shows "Needs retry" and meal detail offers
    "Retry analysis". The `runCatching` stays only to keep the process alive.
    Live failures surface on the Coach turn ("Couldn't finish. Your message is
    saved." with Try again), as on iOS.

  A KDoc line on `MealAnalysisWorker` states that it is sample-only.
- **Process killed mid-turn: a platform `JobScheduler` expedited job, not
  WorkManager and not a bare `shortcut:`.**
  - Android has no `beginBackgroundTask`. Without a job, a turn sent just
    before the person leaves the app can be cut off, and its reply waits until
    the next launch. iOS gives that turn its background time.
  - An expedited job is the platform's equivalent, and minSdk 31 has
    `JobInfo.Builder.setExpedited` natively. WorkManager would add a
    dependency whose value is back-compat below API 31, which Mivu does not
    need. The spec's "expedited WorkManager" is met in kind by the platform
    API it wraps.
  - If the process dies anyway, nothing is lost. The turn is committed, and
    `nextPendingCoachTurn` includes `captured` and `analyzing`, so the startup
    drain resumes it. The job is also rescheduled by the system.
  - iOS posts "Your message is saved" on expiry only for Siri-started turns
    (`CoachReplyNotification.follow`, from `TellCoachIntent`). That stays with
    milestone 8, per the 4c ruling.
- **Consent UI is an M3 `AlertDialog`,** as iOS uses an alert. The iOS
  sentence about the USDA key is dropped, because Android has no nutrition
  source yet. Restore it when that setting ships.
- **Network errors at sign-in get a clearer notice.** It is Android-only copy:
  "Can't reach ChatGPT. Check your internet connection, then try again." It is
  shown for `SessionError.NetworkUnavailable` (DNS failures are
  `UnknownHostException`, an `IOException`). iOS shows "Connection unavailable.
  Try again." for every failure. The note that the emulator may need
  `-dns-server 8.8.8.8` goes in the AGENTS.md Android section.
- **The selected model is not persisted,** as on iOS (`selectedModel` is a
  plain property). It is kept while it is still in the catalog, else the first
  entry.
- **One account.** Android keeps using the first saved registration. The iOS
  `selectedRegistrationID` preference has no Android use while there is one
  account per install.

**Deferred or cut:**
- the iOS "Coach AI" provider picker (Apple Intelligence): it has no Android
  counterpart;
- "Disconnect ChatGPT when the last profile is deleted": Android has no
  profile deletion yet (Settings and day rollover);
- other Settings rows (profiles, goals, preferences, backup, nutrition source,
  day settings): their own milestones;
- receipt links for `profiles`, `nutritionSource` and `backup`: they stay
  hidden until those screens exist;
- the "saved" notification on expiry: milestone 8;
- Data safety answers and the AI-content report row: Play readiness. This
  milestone records what is sent, which those answers need.

## Global Constraints

- **Platform:** minSdk 31, targetSdk 37, platform APIs first, no new
  dependency. `androidx.browser` moves to `implementation` (it is already in
  the version catalog). Predictive back comes from navigation-compose.
- **Credentials:**
  - tokens stay in `CredentialStore` (Keystore-encrypted, excluded from
    backups);
  - nothing logs a token, code, callback URL, prompt or reply;
  - `ChatGPTConnection` keeps only state, never a token;
  - failure text is fixed copy.
- **Consent:**
  - no sign-in starts and no saved session is restored until
    `openAISharingConsent` is true;
  - only the person's tap on "Agree and Continue" sets it;
  - tests set it through the preference fake, never by tapping the release
    dialog on a real account;
  - agents never accept the provider's terms or consent screens for the owner.
- **No paid substitution:** only the person's ChatGPT plan through
  `auth.openai.com` and `api.openai.com/v1`; no API key path and no billing.
  Tests use the loopback fakes and never reach OpenAI. Only Task 5's
  owner-run step does.
- **Synthetic data only:** fixtures use synthetic meals ("two boiled eggs and a
  slice of toast"), synthetic account identities and the synthetic plate photo.
- **Touch targets:** at least 48 dp for every button, link, row and menu item.
- **Copy** (verbatim from iOS unless marked):
  - Settings: "Settings", "Setup", "Coach AI" with the value "ChatGPT" /
    "Connect ChatGPT", "Support", "Privacy Policy", "Calorie and nutrition
    figures are estimates, not medical advice. Check with a doctor or
    registered dietitian before big changes to how you eat.";
  - Coach AI screen:
    - "Uses your ChatGPT Plus or Pro plan. Coach messages and photos you send
      are shared with OpenAI.";
    - "ChatGPT connected" / "Connect for meal analysis";
    - "Coach analysis uses your selected ChatGPT account's plan allowance when
      eligible and is subject to its usage limits. Captures save locally
      without a connection.";
    - "Connecting", "Cancel connection", "Account model", "Disconnect
      ChatGPT", "Manage usage";
  - button titles: "Enable ChatGPT plan usage" (plan permission missing) /
    "Continue with ChatGPT" (no registration) / "Reauthorize ChatGPT";
  - consent: "Share with OpenAI?", the body "To estimate nutrition and answer
    Coach, Mivu sends OpenAI, through your ChatGPT account, what you record:
    meals, photos, messages, weights, workouts, goals and profile details. Your
    diary stays on this phone, and you can disconnect any time in Settings.",
    "Agree and Continue", "Not Now";
  - notices (`ConnectionNotice`):
    - `cancelled` "Connection cancelled";
    - `denied` "Connection permission declined";
    - `unavailable` "Connection unavailable. Try again.";
    - `offline` "Can't reach ChatGPT. Check your internet connection, then try
      again." (Android-only);
    - `quota` "ChatGPT usage limit reached. Open Manage usage in Settings, then
      retry when usage is available.";
    - `permission` "Enable ChatGPT plan usage before sending a request.";
    - `revoked` "Reconnect to authorize plan usage.";
    - `disconnected` "Local credentials removed";
    - `unconfirmed` "Local credentials removed. Remote revocation
      unconfirmed.";
    - `storageFailed` "Local credentials could not be updated. Try again."
      (Android-only; iOS reuses its sample-storage notice);
  - Coach footnote: "Messages save on this phone." + "Connect ChatGPT for
    replies"; connected: "Using ChatGPT plan" + "Manage usage";
  - receipt links: "Open ChatGPT connection" and "Open Settings";
  - plan welcome: "You're using your ChatGPT plan", "Coach and meal analysis
    in Mivu use your ChatGPT plan and count toward its usage limits.", "Got
    it", "Manage usage";
  - meal: "Retry analysis", "This meal changed. Review it before retrying its
    earlier input."
- **Links:** `https://mivuapp.com/privacy` and
  `https://chatgpt.com/settings/usage`, opened with `LocalUriHandler`.
- **Speed:**
  - each task runs only its own test classes, one class per
    `connectedDebugAndroidTest` run;
  - the full suite runs once, in Task 5;
  - reviews are batched after Task 2 and after Task 4, and the final review
    comes after Task 5.

  ```sh
  cd android
  ./gradlew :app:testDebugUnitTest --tests '*<Class>'
  ./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.yakov103.mivu.<pkg>.<Class>
  ```

## Review Focus

1. **The person disconnects while a Coach turn is waiting on the model**:
   - the reply that arrives afterwards is not saved as a success;
   - the turn ends `waitingForConnection` or `needsRetry`, as on iOS;
   - no token survives in the store.

   (Task 1: `disconnectDuringRespondThrowsSessionChanged`)
2. **The app is restarted after an older build saved a sign-in without
   consent**: the session stays unused; Coach says "Connect ChatGPT for
   replies"; nothing is sent. (Task 1: `restoreWithoutConsentStaysDisconnected`)
3. **Sign-in on an emulator or phone with broken DNS**: the screen shows the
   `offline` notice, nothing is deleted, and Continue works again after the
   network returns. (Task 1: `networkFailureShowsOfflineNotice`)
4. **The person leaves the app right after sending**: the turn finishes in the
   expedited job. If the job is stopped, the turn is still pending and the
   next launch resumes it, never as a new capture. (Task 4:
   `stoppedJobLeavesTurnPendingAndRelaunchResumes`)
5. **The ChatGPT plan hits its usage limit or loses permission mid-session**:
   - the Coach AI screen shows the iOS notice and the right button title;
   - waiting turns stay saved;
   - after reauthorizing, they resume without a new send.

   (Task 1: `unauthorizedPausesPlanPermission`, `quotaSetsQuotaNotice`; Task 3:
   `connectingResumesWaitingTurns`)

---

### Task 1: Connection owner

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/connection/ChatGPTConnection.kt`
- Modify:
  - `MivuApplication.kt`:
    - `val chatGPT` replaces `credentials`/`auth`/`connection()`/`model`/`coachInference`;
    - `drainCoach` passes `includeWaitingForConnection = chatGPT.state.value.canInfer`;
    - a collector calls `drainCoach(retryWaiting = true)` when `canInfer`
      turns true;
    - `restore()` runs once at startup;
  - `MainActivity.kt` (CoachHooks `connected` from `chatGPT.state`);
  - `ui/MivuApp.kt` (`CoachHooks.isConnected: () -> Boolean` becomes
    `connected: StateFlow<Boolean>`);
  - `ui/coach/CoachViewModel.kt` and `CoachComposer.kt` (read the flow);
  - `debug/.../ProofSession.kt` (sign-in, models, disconnect and the Coach turn
    go through `app.chatGPT`; it keeps its interrupted-sign-in flag);
  - `analysis/MealAnalysisWorker.kt` (the sample-only KDoc line).
- Test:
  - `android/app/src/test/java/com/yakov103/mivu/connection/ChatGPTConnectionTest.kt`
  - `android/app/src/test/java/com/yakov103/mivu/connection/MemoryPreferences.kt`
    (a `SharedPreferences` fake backed by a map)

**Interfaces:**
- Consumes: `AuthSession`, `CredentialStoring`, `OAuthAttempt`,
  `LoopbackCallback`, `ResponsesClient.models/respond`, and the test fakes
  `FakeAuthServer` and `MemoryCredentialStore` (`AuthSessionTest.kt`).
- Produces:
  - `enum class AccountState { disconnected, connected, planPermissionMissing }`
  - `enum class ConnectionNotice(val text: String)`, with the values and copy
    in Global Constraints.
  - `data class ConnectionState(val account: AccountState = disconnected, val registrationID: String? = null, val models: List<AvailableModel> = emptyList(), val selectedModel: String = "", val isConnecting: Boolean = false, val isDisconnecting: Boolean = false, val notice: ConnectionNotice? = null, val consented: Boolean = false, val planWelcomeSeen: Boolean = false)`
    - `val canInfer get() = account == connected && !isConnecting && !isDisconnecting && models.any { it.slug == selectedModel }`
    - `val showsPlanWelcome get() = account == connected && !planWelcomeSeen`
    - `val buttonTitle: String`, from `ChatGPTConnectButton.defaultTitle`.
  - `class ChatGPTConnection(store: CredentialStoring, auth: AuthSession, client: ResponsesClient, prefs: SharedPreferences, scope: CoroutineScope)` has:
    - `val state: StateFlow<ConnectionState>`;
    - `val auth: AuthSession`, for the debug proof screen only;
    - `suspend fun restore()`. It returns early unless consented. It restores
      the first registration, applies it, and loads models when connected.
    - `fun recordConsent()`, which writes `openAISharingConsent = true`;
    - `fun acknowledgePlanWelcome()`, which writes `chatGPTPlanWelcomeSeen`;
    - `fun connect(open: (String) -> Unit): Job`. It returns early when not
      consented or busy. It bumps the generation, starts `LoopbackCallback`
      before `open(authorizationUrl)`, and waits up to 5 minutes. It then
      establishes the session, clears `pausedRegistrationID` for that
      registration, and loads models. It maps failures:
      - `CancellationException` → `cancelled`;
      - `OAuthError.Denied` → `denied`;
      - `SessionError.NetworkUnavailable` → `offline`;
      - anything else → `unavailable`.
    - `fun cancelConnection()`;
    - `fun selectModel(slug: String)`, ignored unless `slug` is in `models`;
    - `suspend fun disconnect()`. It follows iOS `disconnect`: the state clears
      first, `auth.disconnect()` follows, and the notice is `disconnected` /
      `unconfirmed`, or `storageFailed` with the session re-applied when the
      store throws.
    - `suspend fun respond(input: List<CoachInferenceInput>, tools: JsonObject): CoachInferenceResult`.
      It captures `(generation, registrationID, selectedModel)`. Before the
      token, after it, and after the response it runs iOS `validate()`
      (`SessionError.SessionChanged` on any change). On failure it runs
      `reflectFailure`, which is iOS `reflectFailure` without the probe job:
      - `QuotaReached` → `quota`;
      - `Forbidden` → pause, then `permission`;
      - `Unauthorized` → pause, then `revoked`;
      - `InvalidRefresh` or no session → disconnected and `revoked`;
      - `PlanPermissionMissing` → `planPermissionMissing` and `permission`.

      It rethrows in every case.
  - `MivuApplication.chatGPT: ChatGPTConnection`. Its prefs file is
    `"chatgpt"`, keyed `openAISharingConsent`, `chatGPTPlanWelcomeSeen` and
    `pausedRegistrationID`.
  - `CoachHooks(connected: StateFlow<Boolean>, …)`.

- [ ] **Step 1: Failing tests** in `ChatGPTConnectionTest`. Each uses the
  fakes. A fake browser `open` parses `state` from the URL and GETs the
  loopback callback with a synthetic code. The `HttpServer` models endpoint
  returns two synthetic models.
  - `restoreWithoutConsentStaysDisconnected`: a stored credential, consent
    false → `account == disconnected`, `canInfer` false, zero model requests.
  - `restoreWithConsentLoadsModelsAndSelectsFirst`;
  - `connectRequiresConsent`: `connect` without consent makes zero requests;
  - `connectSuccessConnectsAndKeepsSelectionInCatalog`;
  - `networkFailureShowsOfflineNotice`: the token endpoint is closed, so the
    notice is `offline`, the store is unchanged, and a second `connect` works;
  - `deniedShowsDeniedNotice` (the callback has `error=access_denied`);
  - `cancelShowsCancelled`;
  - `disconnectClearsStateAndReportsOutcome`: the store is empty, and the
    notice is `disconnected` (revoke 200) or `unconfirmed` (revoke 500);
  - `disconnectDuringRespondThrowsSessionChanged`: the responses endpoint
    blocks, `disconnect()` runs, `respond` throws `SessionChanged`, and the
    store is empty;
  - `selectModelChangeDuringRespondThrowsSessionChanged`;
  - `unauthorizedPausesPlanPermission`: 401 → `planPermissionMissing`,
    `revoked`, `buttonTitle == "Enable ChatGPT plan usage"`, and the pause
    survives a new `ChatGPTConnection` on the same prefs;
  - `quotaSetsQuotaNotice`;
  - `canInferFalseWithoutModels`.
- [ ] **Step 2: Run** `./gradlew :app:testDebugUnitTest --tests '*ChatGPTConnectionTest'`.
  Expected: FAIL with unresolved `ChatGPTConnection`.
- [ ] **Step 3: Implement** `ChatGPTConnection.kt`, then rewire
  `MivuApplication`, `MainActivity`, `CoachHooks`, the coach view model and
  composer, and `ProofSession`. Add the `MealAnalysisWorker` KDoc line: "Sample
  mode only, as iOS `processPending`; live meals are analyzed by the Coach."
- [ ] **Step 4: Run** `ChatGPTConnectionTest`, `AuthSessionTest`,
  `ResponsesClientTest`, then the connected classes
  `com.yakov103.mivu.ConnectionProofScreenTest` and
  `com.yakov103.mivu.ui.coach.CoachComposerTest`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu android/app/src/debug/java/com/yakov103/mivu/ProofSession.kt android/app/src/test/java/com/yakov103/mivu/connection
git commit -m "feat(android): own the ChatGPT connection state"
```

### Task 2: Settings, Coach AI screen and consent

**Files:**
- Create:
  - `android/app/src/main/java/com/yakov103/mivu/ui/settings/SettingsScreen.kt`
    (`SettingsScreen` and `ConnectionScreen`);
  - `android/app/src/main/java/com/yakov103/mivu/ui/settings/ChatGPTConnectButton.kt`
    (the button, the consent dialog and `MivuLinks`).
- Modify:
  - `android/app/build.gradle.kts` (`implementation(libs.androidx.browser)`);
  - `ui/MivuApp.kt`:
    - `Route.Settings` and `Route.Connection`;
    - `onProfile` navigates to `Route.Settings`, and its `shortcut:` comment
      goes;
    - `MivuApp` takes `connection: ChatGPTConnection?` (null in tests that do
      not need it).
  - `MainActivity.kt` (passes `app.chatGPT`);
  - drawables `ic_sparkles`, `ic_shield`, `ic_open_in_new`, `ic_person`.
- Test: `android/app/src/androidTest/java/com/yakov103/mivu/ui/settings/ConnectionScreenTest.kt`

**Interfaces:**
- Consumes: `ConnectionState` and the `ChatGPTConnection` methods from Task 1.
- Produces:
  - `object MivuLinks { const val PRIVACY = "https://mivuapp.com/privacy"; const val USAGE = "https://chatgpt.com/settings/usage" }`
  - `@Composable fun ChatGPTConnectButton(state: ConnectionState, onAgree: () -> Unit, onConnect: () -> Unit, title: String = state.buttonTitle, style: ConnectStyle = ConnectStyle.Filled)`,
    with `enum class ConnectStyle { Filled, Link }`:
    - a tap without consent opens the consent `AlertDialog`;
    - "Agree and Continue" calls `onAgree()` then `onConnect()`;
    - "Not Now" only closes;
    - the button is disabled while connecting or disconnecting.
  - `fun Context.openCustomTab(url: String)`, which wraps
    `CustomTabsIntent.Builder().build().launchUrl`.
  - `@Composable fun SettingsScreen(state: ConnectionState, onOpenConnection: () -> Unit, onBack: () -> Unit)`
  - `@Composable fun ConnectionScreen(state: ConnectionState, onAgree: () -> Unit, onConnect: () -> Unit, onCancel: () -> Unit, onSelectModel: (String) -> Unit, onDisconnect: () -> Unit, onBack: () -> Unit)`
- **Settings** (mockup frame 1):
  - a `LargeTopAppBar` "Settings" with Navigate up;
  - a "Setup" group with one `ListItem`: "Coach AI", valued "ChatGPT" when
    connected, else "Connect ChatGPT";
  - a "Support" group with "Privacy Policy" (opens the link) and the estimates
    note.
- **Coach AI** (mockup frames 2–4):
  - a `TopAppBar` "Coach AI";
  - a state card: a check icon with "ChatGPT connected", or a person icon with
    "Connect for meal analysis";
  - the plan footer line and the allowance line;
  - the notice as an error-container row, with `liveRegion = Polite`;
  - while connecting: `CircularProgressIndicator` with "Connecting" and
    "Cancel connection";
  - otherwise the `ChatGPTConnectButton`;
  - an `ExposedDropdownMenuBox` "Account model", only when `models` is not
    empty;
  - "Disconnect ChatGPT" (outlined, error colour), only with a registration;
  - "Manage usage" as a `TextButton` with an open-in-new icon.

- [ ] **Step 1: Failing tests** in `ConnectionScreenTest`, with state values
  and recording lambdas:
  - `profileButtonOpensSettingsAndCoachAiRow` (through `MivuApp`);
  - `settingsRowShowsConnectionValue`;
  - `consentShownBeforeFirstConnect`: tap "Continue with ChatGPT", and the
    dialog text matches the copy exactly;
  - `agreeRecordsConsentThenConnects`: the calls are in the order
    `onAgree, onConnect`;
  - `notNowChangesNothing`;
  - `consentedConnectSkipsDialog`;
  - `connectedShowsModelPickerAndDisconnect`: picking the second model calls
    `onSelectModel(slug)`;
  - `modelPickerHiddenWithoutModels`;
  - `connectingShowsCancel`;
  - `noticeIsAnnounced`;
  - `buttonTitlesFollowState` (all three titles);
  - `targetsAtLeast48dpAtFontScale2`.
- [ ] **Step 2: Run** `ConnectionScreenTest`. Expected: FAIL.
- [ ] **Step 3: Implement** the screens, the button and the routes. In
  `MivuApp`, `onConnect` is `connection.connect { context.openCustomTab(it) }`.
- [ ] **Step 4: Run** `ConnectionScreenTest` and `AppShellTest`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/build.gradle.kts android/app/src/main/java/com/yakov103/mivu android/app/src/main/res/drawable android/app/src/androidTest/java/com/yakov103/mivu/ui/settings
git commit -m "feat(android): add Settings, the Coach AI screen and OpenAI consent"
```

**Review batch 1** (Tasks 1–2) runs here.

### Task 3: Connect and retry from Coach, Today and meals

**Files:**
- Modify:
  - `ui/coach/CoachComposer.kt` (`Footnote`);
  - `ui/coach/CoachReceiptCard.kt` (destination links);
  - `ui/coach/CoachViewModel.kt` (`retryMeal`);
  - `ui/today/TodayScreen.kt` (the plan welcome dialog);
  - `ui/meal/MealDetailScreen.kt` ("Retry analysis" outside sample mode);
  - `ui/MivuApp.kt` (wiring: footnote connect, `onOpenConnection`,
    `onOpenSettings`, meal retry);
  - `diary/CoachTimeline.kt` (`coachTurnForMeal`).
- Test:
  - additions to `CoachComposerTest`, `CoachScreenTest`, the meal detail test
    class in `androidTest/.../ui/meal`, and `CoachTimelineTest`
    (`androidTest/.../diary`);
  - `android/app/src/androidTest/java/com/yakov103/mivu/ui/today/PlanWelcomeTest.kt`

**Interfaces:**
- Consumes: `ConnectionState`, `ChatGPTConnectButton` (`ConnectStyle.Link`),
  `MivuLinks` and `Route.Connection` from Tasks 1–2.
- Produces:
  - `fun DiaryDatabase.coachTurnForMeal(mealID: UUID): UUID?`, a port of iOS
    `coachTurnForMeal`: the newest turn whose `pendingMealID` is the meal and
    whose submission's parent is that meal, with `LIMIT 1`.
  - `fun CoachViewModel.retryMeal(mealID: UUID): Job`. It finds that turn and
    calls `retry(turnID)`. When there is none, it sets the message "This meal
    changed. Review it before retrying its earlier input." It never captures a
    new turn.
- **Footnote** (iOS 378–395):
  - not `canInfer`: "Messages save on this phone." plus
    `ChatGPTConnectButton(title = "Connect ChatGPT for replies", style = Link)`;
  - connected: "Using ChatGPT plan" plus a "Manage usage" link;
  - both links are at least 48 dp.
- **Receipt links:** a receipt with `destination == connection` shows "Open
  ChatGPT connection"; with `settings` it shows "Open Settings". Other
  destinations render nothing.
- **Plan welcome:** Today shows the `AlertDialog` when
  `state.showsPlanWelcome` and no sheet or dialog route is open. "Got it" and
  dismissal call `acknowledgePlanWelcome()`, and "Manage usage" opens the link
  and acknowledges.
- **Meal detail:** "Retry analysis" shows for `needsRetry` or `captured`. In
  sample mode it keeps calling `onMealCaptured`; otherwise it calls
  `coach.retryMeal(mealID)`.

- [ ] **Step 1: Failing tests.**
  - In `CoachComposerTest`:
    - `notConnectedFootnoteOffersConnect`;
    - `connectLinkAsksConsentFirst`;
    - `connectedFootnoteShowsManageUsage`;
    - `connectingResumesWaitingTurns`: a turn is `waitingForConnection`, the
      connected flow flips to true, and the drain hook is called with
      `retryWaiting`.
  - In `CoachScreenTest`:
    - `connectionReceiptOpensConnection`;
    - `unsupportedDestinationShowsNoLink`.
  - In `CoachTimelineTest`:
    - `coachTurnForMealFindsPendingTurn`;
    - `coachTurnForMealIgnoresReceiptOnlyTurns`.
  - In the meal detail test:
    - `liveRetryAnalysisRerunsSameTurn`: the turn count is unchanged and the
      turn is `captured`;
    - `retryWithoutTurnShowsMealChanged`.
  - In `PlanWelcomeTest`:
    - `shownOnceAfterConnect`;
    - `hiddenWhileSheetOpen`.
- [ ] **Step 2: Run** those classes. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** those classes, then `CoachReplyActionsTest`. Expected:
  PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu android/app/src/androidTest/java/com/yakov103/mivu
git commit -m "feat(android): connect and retry from Coach, Today and meals"
```

### Task 4: Background continuation

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/coach/CoachJobService.kt`
- Modify:
  - `AndroidManifest.xml` (the `<service>` with
    `android.permission.BIND_JOB_SERVICE`, `exported="false"`);
  - `MivuApplication.kt` (`hasPendingWork()`, and `scheduleBackgroundDrain()`);
  - `MainActivity.kt` (`onStop` schedules when work is pending);
  - `diary/CoachTimeline.kt` (`hasPendingCoachWork`, if `nextPendingCoachTurn`
    is not enough).
- Test: `android/app/src/androidTest/java/com/yakov103/mivu/coach/CoachJobServiceTest.kt`

**Interfaces:**
- Consumes: `MivuApplication.drainCoach(): Job` and
  `chatGPT.state.value.canInfer`.
- Produces:
  - `class CoachJobService : JobService`:
    - `onStartJob` launches `app.drainCoach(retryWaiting = true)` and calls
      `jobFinished(params, false)` when it completes. It returns `true`.
    - `onStopJob` cancels its own collector (never the turn's committed state)
      and returns `true`, so the system reschedules.
  - `fun MivuApplication.scheduleBackgroundDrain()`. It schedules job ID
    `COACH_JOB = 1` with `setExpedited(true)` and
    `setRequiredNetworkType(NETWORK_TYPE_ANY)`. `JobScheduler.schedule`
    replaces a pending job with the same ID, so this is idempotent. An
    expedited quota refusal falls back to the same job without `setExpedited`.
  - `suspend fun MivuApplication.hasPendingWork(): Boolean`: is there a Coach
    turn in `captured`, `analyzing` or `waitingForNetwork`, or one in
    `waitingForConnection` when `canInfer`?
- **Comment:** add a one-line why at the schedule call: "iOS
  continueInBackground; the saved-message notification is milestone 8."

- [ ] **Step 1: Failing tests** in `CoachJobServiceTest`. They use a fake
  inference installed through the application's test hook, and `adb shell cmd
  jobscheduler run -f` through `UiAutomation` to force the job:
  - `stopWithPendingTurnSchedulesExpeditedJob`: `JobScheduler.getPendingJob(1)`
    is expedited and needs a network;
  - `stopWithNothingPendingSchedulesNothing`;
  - `jobFinishesPendingTurn`: the turn is `completed` and the job is finished;
  - `stoppedJobLeavesTurnPendingAndRelaunchResumes`: the inference blocks, the
    job is stopped (`cmd jobscheduler timeout`), and the turn is not
    `completed`, has no duplicate, and stays `analyzing` or `captured`. A new
    `drainCoach()` completes it, with one turn and one receipt.
- [ ] **Step 2: Run** `CoachJobServiceTest`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `CoachJobServiceTest` and `CoachWorkerTest`. Expected:
  PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml android/app/src/main/java/com/yakov103/mivu android/app/src/androidTest/java/com/yakov103/mivu/coach/CoachJobServiceTest.kt
git commit -m "feat(android): finish Coach turns in an expedited job after leaving the app"
```

**Review batch 2** (Tasks 3–4) runs here.

### Task 5: Live Phase 0 through the app, evidence and parity

**Files:**
- Create:
  - `docs/verification/2026-10-24-android-connection.md`;
  - `docs/verification/android-connection/*.png`.
- Modify:
  - `docs/verification/2026-10-23-android-phase0.md` (items 2–5: the run
    through the release UI);
  - `docs/parity.md` (the rows `chatgpt-connection`, `openai-consent` and
    `connection-plan-use`);
  - `docs/superpowers/plans/android-carried-items.md`;
  - `AGENTS.md` (the Android section gets one line: "If the emulator cannot
    resolve auth.openai.com, start it with `-dns-server 8.8.8.8`.").

- [ ] **Step 1: Run the full suite once** at a clean commit:
  `./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleRelease --rerun-tasks`,
  then `python3 scripts/ci/parity.py` and the `scripts/ci` unit tests.
  - Record the SHA, the emulator, and the counts from the JUnit XML.
  - Never count a skipped or zero-test class.
  - If a class fails, fix it, or record it honestly with its cause.
- [ ] **Step 2: Live run (owner-present, emulator).**
  - Start the emulator with `-dns-server 8.8.8.8,1.1.1.1`, then install the
    debug build without sample mode.
  - Open Settings → Coach AI.
  - The owner reads the consent dialog and taps "Agree and Continue", then
    signs in in the Custom Tab. Agents never tap either for the owner.
  - Record:
    - the connected state, the model list count and the selected model;
    - one synthetic text meal sent in Coach ("two boiled eggs and a slice of
      toast"): the turn completes and the meal appears on Today with
      nutrition;
    - one synthetic plate photo, the same way. No plate image is in
      `fixtures/` yet, so use a drawn plate with no real food or person;
    - sending, then leaving the app at once: the turn completes in the job;
    - Disconnect: the outcome notice, Coach falls back to "Connect ChatGPT for
      replies", and a new message saves as `waitingForConnection`.
  - Never record reply text, tokens or account identifiers beyond "owner
    account".
  - If the owner is not available, record each step as `blocked` and do not
    claim it.
- [ ] **Step 3: Screenshots,** in light, dark and font scale 2.0, compared with
  the mockup:
  - `settings`;
  - `connection-disconnected`;
  - `connection-consent`;
  - `connection-connected`;
  - `coach-connect-footnote`;
  - `meal-retry`.
- [ ] **Step 4: Parity.**
  - `chatgpt-connection`: Android stays `partial` until the physical-phone run
    (AGENTS.md: emulator results never prove sign-in).
  - `openai-consent` and `connection-plan-use`: Android `done`, with this
    record.
  - Note: live meal analysis is the Coach, as on iOS.
- [ ] **Step 5: Carried items.**
  - Remove every Milestone 5 item, each with its outcome from "Scope
    decisions", and the profile-button item from Play readiness.
  - Add to Settings and day rollover: "Disconnect ChatGPT when the last
    profile is deleted", the remaining Settings rows, and the receipt links for
    `profiles`, `nutritionSource` and `backup`.
  - Add the USDA consent sentence to the nutrition-source item.
- [ ] **Step 6: Commit**

```bash
git add docs/verification/2026-10-24-android-connection.md docs/verification/android-connection docs/verification/2026-10-23-android-phase0.md docs/parity.md docs/superpowers/plans/android-carried-items.md AGENTS.md
git commit -m "docs(verification): record the Android ChatGPT connection and live analysis"
```

**Final review** of the whole milestone runs here.
