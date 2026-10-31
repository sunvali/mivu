# Android Foundation and Phase 0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the parity matrix and its CI check, an empty native Android
app, and a debug-only ChatGPT proof screen that runs Phase 0 (sign-in,
authorized inference, real text/photo analysis, token refresh) on an emulator
and then a physical phone.

**Architecture:** One `android/` Gradle project with a single `app` module.
The connection code ports the iOS baseline (`dd5e8c34`) types one-for-one into
`com.yakov103.mivu.connection` and `com.yakov103.mivu.analysis`. It uses only
platform and Jetpack APIs plus Custom Tabs. The parity checker is a Python
standard-library script in `scripts/ci/`, run by the existing Linux `checks`
job.

**Tech Stack:** Kotlin, Jetpack Compose (Material 3), Android Gradle Plugin
with a version catalog, `androidx.browser` (Custom Tabs), `java.net` /
`HttpURLConnection`, `java.security` (RS256, SHA-256), Android Keystore,
JUnit 4, `org.json:json` (test only), the JDK `com.sun.net.httpserver` (test
fakes), and Python 3 `unittest`.

**Spec:** [`docs/superpowers/specs/2026-10-23-android-app-design.md`](../specs/2026-10-23-android-app-design.md)

## Roadmap (one plan per milestone)

This plan is milestone 1. Later plans are written when their milestone starts,
each from the same spec, with owner-approved mockups first where the spec
requires them:

1. **Foundation + Phase 0** (this plan).
2. Storage, durable capture, and two-way archive compatibility (includes the
   iOS test-only fixture PR).
3. Today and Diary with sample mode (mockups first for Diary).
4. Coach capture, history, reply, context, and edit parity.
5. Production ChatGPT connection UI, consent, model selection, and analysis
   worker.
6. Progress, onboarding, rollover, notifications, and reports (mockups first).
7. Pip renderer and gestures (includes the iOS golden-pose fixture PR).
8. Widgets, quick capture, voice, and backup/restore.
9. Play readiness: release build checks, store listing, and policy items.

## Global Constraints

- Application ID `com.yakov103.mivu`; minSdk 31; targetSdk and compileSdk 36.
- Version name read from repo-root `version.txt`. A release version code is
  *last ledger code + 1* from `android/play-uploads.txt`. Debug version code
  is `1`.
- No hosted Android builds. Hosted CI runs Linux script checks only,
  `ubuntu-slim`, 2-minute limit.
- Synthetic inputs only in tests and diagnostics. Never log tokens or token
  responses. No credentials in the APK, backups or transfers.
- Every dependency beyond platform/Jetpack is justified in its PR.
- Sign-in contract, verbatim from iOS:
  - authorize URL `https://auth.openai.com/api/accounts/authorize`;
  - token `https://auth.openai.com/api/accounts/oauth/token`;
  - revoke `https://auth.openai.com/api/accounts/oauth/revoke`;
  - JWKS `https://auth.openai.com/.well-known/jwks.json`;
  - scope `openid profile email offline_access resource.invoke chatgpt.tokens.use.direct`;
  - resource `https://api.openai.com/v1`;
  - redirect `http://127.0.0.1:<port>/auth/callback`, never `localhost`;
  - first registration `client_id=dynamic_agent_client` plus `agent_name_hint=Mivu`;
  - host ID format `urn:uuid:<lowercase uuid>`.
- Responses requests send `"store": false, "stream": true` and only the
  fields iOS allows.
- Conventional Commit titles; commit as the owner's configured identity; no
  tool or assistant names in commits or PRs.

## Review Focus

1. **Callback with the wrong `state`, an `error=access_denied`, or a second
   hit** → rejected, with no token exchange; `access_denied` is "denied", not
   a generic failure. (Task 4)
2. **App backgrounded while the Custom Tab is open, and the process killed**
   → no crash on return; the attempt is abandoned cleanly and a fresh sign-in
   works. (Task 9, physical-phone check)
3. **Refresh returns `refresh_token_reused` / `invalid_grant`** → tokens
   cleared, sign-in requested; a network timeout leaves credentials intact.
   (Task 6)
4. **A stored credential record that fails validation** (wrong issuer, the
   `dynamic_agent_client` placeholder, missing scopes) → treated as signed
   out, never used. (Task 7)
5. **Matrix rows with `done` but a verification record lacking the SHA or test
   name** → CI fails with the row ID in the message. (Task 1)

---

### Task 1: Parity matrix and CI check

**Files:**
- Create: `docs/parity.md`
- Create: `scripts/ci/parity.py`
- Create: `scripts/ci/test_parity.py`
- Modify: `.github/workflows/ci.yml` (checkout `fetch-depth: 2`; add the parity step)
- Modify: `scripts/ci/test_workflow_contract.py` (only if it pins the checkout inputs or step list)

**Interfaces:**
- Produces:
  - `parse(text: str) -> list[dict]` with keys `id, feature, scope, spec, ios, android, evidence, notes`;
  - `errors(rows, root: Path) -> list[str]`;
  - `needs_update(changed: list[str], body: str) -> bool`;
  - `main(argv) -> int`, which reads changed files from `git diff --name-only HEAD^1 HEAD` and the PR body from `$GITHUB_EVENT_PATH`.

- [ ] **Step 1: Write failing tests** in `test_parity.py`:
  - `test_rejects_duplicate_ids`;
  - `test_rejects_unknown_status` (`"finished"`) and `test_rejects_unknown_scope`;
  - `test_done_requires_evidence_link` (empty evidence → error containing the row id);
  - `test_evidence_record_must_name_tests_and_sha`: a temp record without a 40-hex SHA → error; with SHA and the test name → no error;
  - `test_shared_paths_need_matrix_change`: `needs_update(["android/app/x.kt"], "")` is `True`, `needs_update(["android/app/x.kt", "docs/parity.md"], "")` is `False`, `needs_update(["design-system/mivu/x"], "Parity: unchanged - asset rename")` is `False`, and `needs_update(["README.md"], "")` is `False`;
  - `test_repository_matrix_is_valid`, which runs `errors(parse(docs/parity.md))` and expects `[]`.

  Statuses are `done, partial, pending, equivalent, blocked, n/a`. Scopes are
  `baseline, post-baseline`. Watched prefixes: `ios/`, `android/`, `fixtures/`,
  `design-system/mivu/`.

- [ ] **Step 2: Run** `python3 -m unittest scripts/ci/test_parity.py`. Expected: FAIL (module missing).

- [ ] **Step 3: Implement `parity.py`**. Parse the first Markdown table under
  `## Features`. The Evidence cell holds
  `iOS: <record path> [TestA, TestB] · Android: <record path> [TestC]`, with
  either side `-` when its status needs no evidence. The linked record must
  contain every bracketed test name and a 40-hex source SHA.
- [ ] **Step 4: Write `docs/parity.md`.** Add one row per Feature map entry in
  the spec, plus `report-coach-reply` (scope `baseline`, both `pending`, note
  "only if AI-content policy applies").
  - IDs: `onboarding, today, day-rollover, diary, meal-edit, coach-capture,
    coach-history, coach-reply, coach-context, coach-voice, coach-edit-parity,
    progress, chatgpt-connection, openai-consent, settings, folder-backup,
    archive, reports, analyzed-notification, quick-capture, widgets,
    live-activity, pip, app-icon, sample-mode, store-readiness,
    report-coach-reply`.
  - iOS status and evidence come from the matching `docs/verification/`
    record as it was at `dd5e8c34`: `done` only where the record names
    passing tests and a SHA; otherwise `partial`.
  - Android is `pending`, except `live-activity`, which is `n/a` with the
    spec's reason.
  - Post-baseline rows: `siri-coach` (`docs/verification/2026-10-23-siri-coach.md`)
    and anything merged after `dd5e8c34`. List `git log --oneline dd5e8c34..origin/main`
    and add one row per `feat` commit.
- [ ] **Step 5: Wire CI.** In `ci.yml`, set checkout `fetch-depth: 2` and add
  the step `python3 scripts/ci/parity.py`. Update the workflow contract test if
  it fails.
- [ ] **Step 6: Run** `python3 -m unittest discover -s scripts/ci -p 'test_*.py'`. Expected: all pass.
- [ ] **Step 7: Commit** `ci(parity): track iOS and Android feature parity`.

### Task 2: Android project skeleton

**Files:**
- Create: `android/settings.gradle.kts`, `android/build.gradle.kts`, `android/gradle.properties`, `android/gradle/libs.versions.toml`, Gradle wrapper files
- Create: `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`
- Create: `android/app/src/main/java/com/yakov103/mivu/MainActivity.kt`
- Create: `android/app/src/main/res/xml/data_extraction_rules.xml`
- Create: `android/play-uploads.txt` (header comment only)
- Create: `scripts/ci/play_ledger.py`, `scripts/ci/test_play_ledger.py`
- Modify: `.gitignore` (`android/.gradle/`, `android/build/`, `android/app/build/`, `android/local.properties`, `*.keystore`, `*.jks`)

**Interfaces:**
- Produces: a Gradle function `nextVersionCode(ledger: File): Int` in
  `app/build.gradle.kts` (last non-comment line's first field + 1, or 1 when
  empty). Release variants use it; debug uses `1`.
- Produces: `play_ledger.errors(text) -> list[str]` (codes strictly
  increasing, five fields per line: `code name sha date track`), wired into the
  CI step next to `parity.py`.

- [ ] **Step 1: Failing tests** in `test_play_ledger.py`:
  - `test_codes_must_increase` (`2 …` after `3 …` → error);
  - `test_duplicate_code_rejected`;
  - `test_empty_ledger_ok`;
  - `test_repository_ledger_valid`.
- [ ] **Step 2: Run** `python3 -m unittest scripts/ci/test_play_ledger.py`. Expected: FAIL.
- [ ] **Step 3: Implement `play_ledger.py`** and add `python3 scripts/ci/play_ledger.py android/play-uploads.txt` to the CI step.
- [ ] **Step 4: Create the project.** Use the current Android Studio "Empty
  Activity" (Compose) template versions, pinned in `libs.versions.toml`.
  `applicationId`/`namespace` `com.yakov103.mivu`, min 31, target/compile 36,
  `versionName` = trimmed `../version.txt`. Release builds set
  `isMinifyEnabled = true`.
  - Manifest: `android:allowBackup="true"`,
    `android:dataExtractionRules="@xml/data_extraction_rules"`, and only the
    INTERNET permission.
  - `MainActivity` shows a Material 3 `Scaffold` with the text "Mivu",
    edge-to-edge.
- [ ] **Step 5: Write `data_extraction_rules.xml`.**
  - `<cloud-backup>`: exclude domains `database`, `file`, `sharedpref`, and
    `external` (path `.`).
  - `<device-transfer>`: include `database` and `file`.
  - `<cross-platform-transfer>`: exclude domains `database`, `file`,
    `sharedpref`, and `external` (path `.`).
  - Credentials live in `noBackupFilesDir`, which is always excluded.
- [ ] **Step 6: Verify** with `cd android && ./gradlew :app:assembleDebug :app:testDebugUnitTest`. Expected: BUILD SUCCESSFUL. Then `./gradlew :app:bundleRelease -x lint` fails only for missing signing, or succeeds unsigned.
- [ ] **Step 7: Run** `python3 -m unittest discover -s scripts/ci -p 'test_*.py'`. Expected: pass.
- [ ] **Step 8: Commit** `feat(android): add native Android project skeleton`, and set the `docs/parity.md` note "skeleton only" (no status change).

### Task 3: Contributor rules for Android

**Files:**
- Modify: `AGENTS.md` (new `## Android` section, at most 12 lines)
- Modify: `scripts/ci/git_hooks.py`, `scripts/ci/test_git_hooks.py`

**Interfaces:**
- Produces: hook constant `ANDROID = ('android',)`. Pre-push runs
  `./gradlew :app:testDebugUnitTest` from `android/` only when the tree of
  `ANDROID` differs from the baseline. This mirrors `NATIVE`.

- [ ] **Step 1: Failing test** `test_android_units_run_only_when_android_changes` in `test_git_hooks.py`, following the existing iOS native test's pattern.
- [ ] **Step 2: Run** `python3 -m unittest scripts/ci/test_git_hooks.py`. Expected: FAIL.
- [ ] **Step 3: Implement** in `git_hooks.py`, reusing `tree()`/`clean()` the same way `NATIVE` does.
- [ ] **Step 4: Run** the full `scripts/ci` suite. Expected: pass.
- [ ] **Step 5: Write the AGENTS.md section.** Cover:
  - use Gradle and an emulator in place of XcodeBuildMCP;
  - record the SHA, device/API level, and counts in `docs/verification/`;
  - emulator evidence doesn't prove camera, sign-in or notifications;
  - follow the spec link and `docs/parity.md` rules;
  - the upload ledger rule.
- [ ] **Step 6: Commit** `docs(android): add Android contributor rules and push check`.

### Task 4: OAuth attempt

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/connection/OAuthAttempt.kt`
- Test: `android/app/src/test/java/com/yakov103/mivu/connection/OAuthAttemptTest.kt`

**Interfaces:**
- Produces:
  - `sealed class OAuthError : Exception` with objects `InvalidRedirect`, `InvalidRegistration`, `InvalidCallback`, `Denied`, `ProviderError`, `AlreadyConsumed`;
  - `data class AuthorizationCode(val code: String, val issuedClientID: String, val redirect: String)`;
  - `class OAuthAttempt private constructor(...)` with `val state, nonce, verifier, callback: String`, `val authorizationUrl: String`, `fun consumeCallback(url: String): AuthorizationCode`, and `companion fun make(hostID: String, issuedClientID: String?, callback: String, requestPlanConsent: Boolean = false): OAuthAttempt`;
  - `fun challenge(verifier: String): String`.

- [ ] **Step 1: Failing tests:**
  - `challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")` equals
    `"E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"` (RFC 7636 vector);
  - first registration URL has `client_id=dynamic_agent_client`,
    `agent_name_hint=Mivu`, the exact scope and resource,
    `code_challenge_method=S256`, and no `prompt`;
  - reauthorization with `"oaiapp_x"` has no `agent_name_hint`;
  - `requestPlanConsent=true` adds `prompt=consent`;
  - `make` throws `InvalidRedirect` for `http://localhost:1455/auth/callback`,
    `https://127.0.0.1:1455/auth/callback`,
    `http://127.0.0.1:1455/callback`, and a URL with a query;
  - `make` throws `InvalidRegistration` for `issuedClientID = "dynamic_agent_client"` and for `""`;
  - `consumeCallback` with the wrong state throws `InvalidCallback`;
    `error=access_denied` throws `Denied`; another error throws
    `ProviderError`; a second call throws `AlreadyConsumed`; a valid call
    returns the code plus the `client_id` from the callback.
- [ ] **Step 2: Run** `./gradlew :app:testDebugUnitTest --tests '*OAuthAttemptTest'`. Expected: FAIL.
- [ ] **Step 3: Implement.** State, nonce and verifier are 32 `SecureRandom` bytes, base64url without padding. Use `android.net.Uri`-free parsing (`java.net.URI`) so JVM tests run.
- [ ] **Step 4: Run** the same tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): build and verify OAuth attempts`.

### Task 5: Loopback callback listener

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/connection/LoopbackCallback.kt`
- Test: `android/app/src/test/java/com/yakov103/mivu/connection/LoopbackCallbackTest.kt`

**Interfaces:**
- Produces: `class LoopbackCallback : AutoCloseable` with
  - `fun start(): String`, which binds `127.0.0.1` on port 0 and returns `http://127.0.0.1:<port>/auth/callback`;
  - `suspend fun await(): String`, which returns the full callback URL;
  - `close()`.

- [ ] **Step 1: Failing tests:**
  - `start()` returns a `127.0.0.1` URL whose socket is bound to the loopback
    address only;
  - a GET to the path completes `await()` with the query intact, and the
    browser gets a 200 HTML page saying "You can return to Mivu";
  - a GET to `/other` gets 404 and doesn't complete;
  - after `close()`, `await()` throws `CancellationException`;
  - a second `await()` while one is waiting throws `IllegalStateException`.
- [ ] **Step 2: Run** the tests. Expected: FAIL.
- [ ] **Step 3: Implement** with a single-thread `ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"))` and minimal HTTP/1.1 request-line parsing. Don't add an HTTP server dependency.
- [ ] **Step 4: Run** the tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): receive the sign-in callback on 127.0.0.1`.

### Task 6: Token exchange, refresh, revoke and ID-token validation

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/connection/AuthSession.kt`, `IdTokenValidator.kt`, `Credentials.kt`
- Test: `AuthSessionTest.kt`, `IdTokenValidatorTest.kt` (JDK `HttpServer` fake for the endpoints; endpoints injectable as base URL for tests only)

**Interfaces:**
- Consumes: `AuthorizationCode` (Task 4).
- Produces:
  - `data class VerifiedIdentity(issuer: String, subject: String)`;
  - `data class AccountRegistration(identity: VerifiedIdentity, issuedClientID: String)` with `id` = lowercase hex SHA-256 of the JSON array `[issuer, subject, issuedClientID]` (as on iOS);
  - `data class Credentials(registration: AccountRegistration, accessToken: String, refreshToken: String?, idToken: String, scopes: Set<String>, expiresAtEpochSec: Long)` with `planPermissionGranted` (`resource.invoke` and `chatgpt.tokens.use.direct`);
  - `sealed class SessionError` with `NoActiveSession`, `PlanPermissionMissing`, `InvalidRegistration`, `IdentityMismatch`, `InvalidResponse`, `NetworkUnavailable`, `ProviderFailure(code)`, `InvalidRefresh`;
  - `class AuthSession(store: CredentialStoring, http: Endpoints)` with `suspend fun establish(code, verifier, nonce): Credentials`, `suspend fun accessToken(nowSec: Long): String`, and `suspend fun disconnect(): RevocationOutcome`;
  - `IdTokenValidator.validate(token, jwks: String, clientID, nonce, nowSec): VerifiedIdentity`.

- [ ] **Step 1: Failing tests:**
  - `establish` posts form fields `grant_type=authorization_code`, `client_id`,
    `code`, `code_verifier`, `redirect_uri`, `resource`;
  - a reply with `offline_access` but no refresh token → `InvalidResponse`;
  - a non-`bearer` token type → `InvalidResponse`;
  - `accessToken` returns the stored token while expiry is more than 30 s
    away (the iOS margin). Otherwise it refreshes, replacing access token,
    refresh token, expiry and scopes together. With no refresh token it
    deletes the credentials and throws `InvalidRefresh`;
  - each of `invalid_grant`, `invalid_refresh_token`, `token_expired`,
    `refresh_token_expired`, `refresh_token_invalidated`,
    `refresh_token_reused` → `InvalidRefresh` and the stored credentials are
    deleted;
  - a socket timeout → `NetworkUnavailable` and credentials are kept;
  - two concurrent `accessToken` calls make one refresh request;
  - validator rejects alg `HS256`, an unknown `kid`, a bad signature, a wrong
    `iss` (anything but `https://auth.openai.com`), a wrong `aud`, a wrong
    nonce, and an expired token. A token signed by a test RSA key and served
    in test JWKS passes.
- [ ] **Step 2: Run** the tests. Expected: FAIL.
- [ ] **Step 3: Implement** with `HttpURLConnection`, `org.json` (platform on device, `testImplementation` on JVM), `java.security.Signature("SHA256withRSA")`, and a `Mutex` for single-flight refresh.
- [ ] **Step 4: Run** the tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): exchange, refresh and revoke ChatGPT tokens`.

### Task 7: Credential store

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/connection/CredentialStore.kt`
- Test: `android/app/src/androidTest/java/com/yakov103/mivu/connection/CredentialStoreTest.kt` (instrumented, emulator)

**Interfaces:**
- Produces:
  - `interface CredentialStoring` with `hostID(): String`, `registrations(): List<AccountRegistration>`, `load(id): Credentials?`, `replace(c: Credentials)`, and `delete(id)`;
  - `class CredentialStore(context)` storing AES-GCM records encrypted with Keystore key alias `mivu.account-sessions` under `noBackupFilesDir/accounts/`.

- [ ] **Step 1: Failing tests:**
  - `hostID()` is stable across calls and matches `^urn:uuid:[0-9a-f-]{36}$`;
  - `replace` then `load` round-trips;
  - a record with issuer other than `https://auth.openai.com`, or with
    `issuedClientID == "dynamic_agent_client"`, loads as `null`;
  - files are under `context.noBackupFilesDir`;
  - raw file bytes don't contain the access token string.
- [ ] **Step 2: Run** `./gradlew :app:connectedDebugAndroidTest --tests '*CredentialStoreTest'` on an API 36 emulator. Expected: FAIL.
- [ ] **Step 3: Implement** with a `KeyGenParameterSpec` AES/GCM/NoPadding 256-bit key and atomic writes (temp file + rename).
- [ ] **Step 4: Run** the tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): keep ChatGPT credentials in Keystore-encrypted storage`.

### Task 8: Responses client

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/analysis/ResponsesClient.kt`
- Test: `ResponsesClientTest.kt`, with SSE fixtures in `fixtures/responses/` (synthetic; repo root, read via a Gradle `test` resources srcDir)

**Interfaces:**
- Produces:
  - `class ResponsesClient(base = "https://api.openai.com/v1/")` with `suspend fun models(accessToken): List<AvailableModel>` and `suspend fun run(model: String, text: String, image: ByteArray?, mime: String?, accessToken: String): ProbeResult`;
  - `data class ProbeResult(val text: String)`;
  - `sealed class Failure` with `InvalidInput`, `Unauthorized`, `Http(code)`, `Malformed(reason)`.

- [ ] **Step 1: Failing tests:**
  - the request body has exactly `model`, `input`, `store=false`,
    `stream=true`, and the headers are `Authorization: Bearer …`,
    `Accept: text/event-stream`;
  - an image becomes an `input_image` with
    `image_url = "data:image/jpeg;base64,…"`;
  - the fixture `text-ok.sse` yields the concatenated `output_text`;
  - `truncated.sse` → `Malformed`; 401 → `Unauthorized`;
  - the token never appears in any `Failure` message.
- [ ] **Step 2: Run** the tests. Expected: FAIL.
- [ ] **Step 3: Implement** a line-based SSE reader over `HttpURLConnection` that handles only the event types the iOS parser accepts at `dd5e8c34` (`ResponsesClient.swift`).
- [ ] **Step 4: Run** the tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): run Responses requests under the ChatGPT plan`.

### Task 9: Debug proof screen and Phase 0 record

**Files:**
- Create: `android/app/src/debug/java/com/yakov103/mivu/ConnectionProofActivity.kt`, `android/app/src/debug/AndroidManifest.xml`
- Modify: `android/gradle/libs.versions.toml`, `android/app/build.gradle.kts` (add `androidx.browser`, justified as Custom Tabs, the platform-recommended way to open the system browser)
- Create: `docs/verification/2026-10-23-android-phase0.md`

**Interfaces:**
- Consumes: `OAuthAttempt`, `LoopbackCallback`, `AuthSession`, `CredentialStore`, `ResponsesClient`.
- Produces: a debug-only screen with these buttons:
  - "Sign in";
  - "List models";
  - "Analyze text" (a synthetic "two boiled eggs and a slice of toast");
  - "Analyze photo", which opens the system photo picker so the owner picks a test meal photo;
  - "Force refresh";
  - "Disconnect".

  Each shows pass/fail and a redacted status, never a token.

- [ ] **Step 1: Instrumented UI test** `ConnectionProofScreenTest`: the
  screen launches, all six buttons have content descriptions and are at
  least 48 dp, and "Sign in" starts a loopback listener and fires a
  `CustomTabsIntent`. Use Espresso-Intents to stub the browser.
- [ ] **Step 2: Run** on the emulator. Expected: FAIL.
- [ ] **Step 3: Implement.** The listener starts before the Custom Tab
  opens. If the process dies with an attempt in flight, the next launch
  shows "Sign-in was interrupted, try again" and drops the attempt.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Write `2026-10-23-android-phase0.md`.** It holds the six
  Phase 0 items from the spec, each with fields: environment (emulator or
  device, API), source SHA, steps run, result
  (`pass`/`fail`/`blocked`), and notes. Pre-fill item 1 (eligibility) and
  item 6 (reviewer access) as `blocked`, awaiting a written answer, with the
  spec's citations. Live items stay `not run` until the owner performs
  sign-in.
- [ ] **Step 6: Commit** `feat(android): add the Phase 0 ChatGPT proof screen`.
- [ ] **Step 7: Owner-run live proof.**
  - On the emulator, then on a physical phone, the owner signs in, and the
    agent records results for items 2 to 5 in the record.
  - The live run proves the redirect comes back from the Custom Tab with the
    app backgrounded, and that sign-in works again after a forced process
    kill.
  - Commit `docs(verification): record Android Phase 0 results`. Set
    `docs/parity.md` `chatgpt-connection` Android to `partial` with that
    evidence link; it is not `done` until milestone 5.
