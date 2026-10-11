# Native iPhone Connection Proof Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove that a native iPhone app can authorize the user's own ChatGPT plan and complete one synthetic image request without a computer in the user flow.

**Architecture:** A small SwiftUI diagnostic app presents system-browser authorization, validates identity and permissions, and calls the documented inference endpoint. Credentials live in Keychain; synthetic jobs persist locally and recover from interruption. This first slice tests the design's central dependency before implementing the diary and cloud backup.

**Tech Stack:** Swift 6 language mode, SwiftUI, AuthenticationServices, Network, CryptoKit, Security, URLSession, Swift Testing. JOSESwift 3.0.0 is the single proposed dependency, for signed token verification rather than handwritten cryptography.

**Spec:** `docs/superpowers/specs/2026-10-11-food-logger-design.md`

## Global Constraints

- iPhone first. Connecting ChatGPT and everyday use must work without a computer.
- Use native Swift for the iPhone application.
- Analysis uses each user's own ChatGPT plan through official authorization.
- Keep a small analysis boundary that permits a later server worker.
- Apply the ponytail skill throughout implementation: minimal complete code, human-readable Swift, and current Swift platform practices.
- UI switches between Hebrew RTL and English LTR; input accepts both languages.
- Never buy credits, enable billing, or substitute paid API access without explicit approval.
- Only synthetic text/images are used in this proof; credentials and provider responses are never committed or printed.
- No dependency on Siri beta, Apple model substitution, public signup, cloud resources, nutrition scoring, or production claims in this slice.
- Target iOS 26.0 for the proof; iOS 27 Siri work stays isolated for the later diary plan.
- Make a separate GitHub repository only after the owner identifies the intended repository. Never reuse or modify an excluded repository.
- New repository visibility defaults to private. If documented eligibility requires public source, stop for that specific publication decision.
- Do not mention prohibited workflow branding in commits or pull requests. Use `feature/native-connection-proof` for the implementation branch.

## Review Focus

- A callback is replayed or has duplicate parameters: consume one matching attempt once; reject ambiguous input.
- The browser is canceled or the app is killed during sign-in: do not replace the current connection or retain reusable authorization codes.
- An apparently successful HTTP stream ends early: report incomplete work and retain the job; no completed result is invented.
- Two requests refresh an expired session together: perform one refresh and atomically retain the replacement refresh token.
- The phone loses network or is locked while processing: persist the job, stop safely, and resume only when the app may execute.

Each condition has a test in the owning task below. Live phone evidence is separate from simulated tests.

## Scope and prerequisites

This is the first implementation plan, not a claim that the full MVP is complete.
The spec's diary, tracking days, corrections, backup, export/deletion, and three
Siri shortcuts follow after the connection gate passes and storage/identity costs
are established. They are intentionally not implemented against an unproven
authorization route. The next plan must cover those requirements before their
implementation.

Read-only checks on 2026-10-11 found Xcode 27.0 and the build-tool CLI installed.
Simulator inventory failed because the Xcode license agreement has not been
accepted. The owner must review/accept the agreement in Xcode before builds or
tests can run. Record unavailable checks as `NOT_RUN_BLOCKED`; never accept legal
terms on the owner's behalf. Physical-device signing/trust and actual account
consent may also require owner interaction.

The owner requested `yakov103/mivu`, created privately with the GitHub CLI
on 2026-10-11. The clean clone initially contains only a README on `main`.
The owner approved this plan and native execution with independent review.
Product name, project, and scheme are Mivu; bundle identifier is
`com.yakov103.mivu`. Preserve unrelated content and use a feature branch.

## File map

Paths are relative to the approved product repository. Move/copy only this app's
reviewed design documents into that repository; do not import other projects.

- `README.md`, `AGENTS.md`, `.gitignore`: project purpose, minimal Swift/skill conventions, verification instructions, and secret/build exclusions.
- `ios/Mivu.xcodeproj/`: native app project, shared `Mivu` scheme, Swift Testing target, iOS 26 deployment target; adapt the scaffold into this explicit layout.
- `ios/Mivu/MivuApp.swift`: application entry and dependency composition.
- `ios/Mivu/ConnectionProofView.swift`: connection/probe status, language setting, and synthetic request controls.
- `ios/Mivu/Connection/OAuthAttempt.swift`: immutable attempt, PKCE and query construction, validated callback parsing.
- `ios/Mivu/Connection/LoopbackCallback.swift`: one-shot listener bound only to 127.0.0.1.
- `ios/Mivu/Connection/IDTokenValidator.swift`: published JWKS signature verification and claim validation.
- `ios/Mivu/Connection/ChatGPTConnection.swift`: account state, exchange/renew/revoke operations, serialized refresh.
- `ios/Mivu/Connection/CredentialStore.swift`: protected Keychain read/replace/delete, stable host ID.
- `ios/Mivu/Analysis/ResponsesClient.swift`: account model discovery, one streaming request, strict completion/error handling.
- `ios/Mivu/Analysis/ProbeJob.swift`: Codable probe state and atomic persistence/recovery.
- `ios/Mivu/Localizable.xcstrings`: English/Hebrew labels and errors.
- `ios/MivuTests/`: tests named in the tasks; synthetic signing keys and network fixtures are generated in tests or visibly synthetic.
- `docs/verification/2026-10-11-native-connection-proof.md`: results and human gates, without credentials, callback queries, or meal data.
- `docs/adr/0001-native-integration-decision.md`: evidence-backed eligibility/callback decision and next infrastructure choices.

No additional generic service/repository framework, global state package, or web frontend is required.

## Verification commands

After the owner accepts the Xcode license, discover an available iPhone simulator
with `xcodebuildmcp simulator list --enabled true`. Select its UUID and set
`MIVU_SIMULATOR_ID` in the terminal; this is the only environment variable
used below. Inspect CLI project/session defaults before building and use explicit
paths/scheme to avoid a different project's defaults.

Targeted test command, with the task's test-class name substituted for CLASS:

```sh
rtk proxy xcodebuildmcp simulator test --project-path ios/Mivu.xcodeproj --scheme Mivu --simulator-id "$MIVU_SIMULATOR_ID" --extra-args '-only-testing:MivuTests/CLASS'
```

Aggregate command:

```sh
rtk proxy xcodebuildmcp simulator test --project-path ios/Mivu.xcodeproj --scheme Mivu --simulator-id "$MIVU_SIMULATOR_ID"
```

The command must exit successfully and the test report must show the named tests
executed with zero failures. CLI availability or compilation alone is not a
test pass. Verify `rtk proxy` availability before using it; run the same CLI
directly if unsupported. Record command, date/time, environment, commit, exit
status, counts, and remaining gates for every completed task.

### Task 1: Repository and runnable native proof screen

**Files:** Create the entry/project files, `README.md`, `AGENTS.md`, `.gitignore`, `Localizable.xcstrings`, and `ios/MivuTests/ProofStateTests.swift`.

**Interfaces:** `enum ProofState: Equatable { case disconnected, connecting, connected, planPermissionMissing, quotaReached, unavailable, analyzing, completed }`; `ConnectionProofView` initially displays `.disconnected` and no completed result. Constructing `ChatGPTConnection()` starts disconnected without reading saved credentials or sending requests; saved-registration restoration is an explicit app-launch operation.

- [x] Verify the supplied repository and its instructions; create a new private repository only if requested. Bootstrap a new repository with reviewed docs, then put implementation on `feature/native-connection-proof`; use PRs for subsequent changes to the default branch.
- [x] Generate a native SwiftUI scaffold with `xcodebuildmcp project-scaffolding scaffold-ios`, project name `Mivu`, output `ios`, bundle identifier `com.yakov103.mivu`, display name `Mivu`, and deployment target `26.0`. Normalize to the file map, retaining only the app and test targets needed for this proof. Do not change account signing or paid capabilities automatically.
- [x] Write the initial state test before connecting behavior (red run blocked by license):

```swift
@Test func initialConnectionDoesNotClaimInference() {
    let connection = ChatGPTConnection()
    #expect(connection.state == .disconnected)
    #expect(connection.lastCompletedProbe == nil)
}
```

- [ ] Run `ProofStateTests` and confirm the missing connection implementation fails; then add the minimal `@MainActor` connection state and native proof screen. Use system typography/SF Symbols, supported touch targets, and labeled English/Hebrew UI. Show queued/analyzing/completed separately.
- [ ] Run the test successfully, then `xcodebuildmcp simulator build-and-run` with the explicit project/scheme/simulator. Inspect light/dark, larger text, VoiceOver labels, Hebrew RTL, and reduced motion. Commit exact files with `feat: add native connection proof screen`.

### Task 2: One-shot official authorization callback

**Files:** Create `OAuthAttempt.swift`, `LoopbackCallback.swift`, and `ios/MivuTests/OAuthAttemptTests.swift`; modify `ChatGPTConnection.swift` and `ConnectionProofView.swift`.

**Interfaces:** `OAuthAttempt.make(hostID: String, issuedClientID: String?, callbackURL: URL) throws -> OAuthAttempt`; properties `state`, `nonce`, `verifier`, `callbackURL`, `authorizationURL`. Its mutating `consumeCallback(_ url: URL) throws -> AuthorizationCode` returns `code`, `issuedClientID`, and the exact redirect URL once. `LoopbackCallback.start() async throws -> URL`, `receive() async throws -> URL`, `stop()`.

- [ ] Add failing `OAuthAttemptTests`: first registration uses `dynamic_agent_client`; an issued ID is retained on reauthorization; `S256` matches a known PKCE vector; callback scheme/host/path/port matches the attempt; wrong state, duplicate query fields, missing issued ID, changed returning client ID, replay, and `access_denied` are rejected. Assert denied attempts never call the exchange transport.

```swift
@Test func rejectsAnotherAttemptsState() throws {
    let callback = try #require(URL(string: "http://127.0.0.1:1455/auth/callback"))
    var attempt = try OAuthAttempt.make(hostID: "fixture-host", issuedClientID: nil, callbackURL: callback)
    let wrong = try #require(URL(string: "http://127.0.0.1:1455/auth/callback?state=wrong&code=fixture&client_id=oaiapp_fixture"))
    #expect(throws: (any Error).self) { try attempt.consumeCallback(wrong) }
}
```
- [ ] Run the targeted test and confirm failure before implementation.
- [ ] Generate cryptographic attempt values with CryptoKit/Security and construct URLComponents query items from the current official registration page. Request `openid profile email offline_access resource.invoke chatgpt.tokens.use.direct` and resource `https://api.openai.com/v1`. Use `agent_name_hint=Mivu` for first registration only. Never persist `dynamic_agent_client` as the issued registration ID.
- [ ] Implement a bounded, one-shot Network listener on `127.0.0.1` only, path `/auth/callback`, ephemeral port, 16 KiB maximum request headers, GET only, and five-minute attempt timeout. Stop on success/cancellation/expiry. Render a generic completion page without echoing query values; do not log requests. Validate callback state before exchange.
- [ ] First test a synthetic round trip through `ASWebAuthenticationSession` with no provider credentials. The loopback listener receives the callback; stop the browser session after the validated callback is consumed. Treat the ensuing cancellation completion as expected only for that consumed attempt. Record actual app/browser behavior; do not substitute a custom-scheme OAuth redirect or a desktop helper.
- [ ] Run all callback tests and verify the listener rejects nonmatching requests without losing the valid pending attempt. If the documented route cannot work on iPhone, stop live provider integration and record the exact blocker. Otherwise commit `feat: add one-shot native authorization callback`.

### Task 3: Verified identity and protected credential lifecycle

**Files:** Create `IDTokenValidator.swift`, `CredentialStore.swift`, `ios/MivuTests/IDTokenValidatorTests.swift`, and `ios/MivuTests/ConnectionTests.swift`; modify `ChatGPTConnection.swift` and project package configuration.

**Interfaces:** `IDTokenValidator.validate(_ token: String, jwks: Data, clientID: String, nonce: String, now: Date) throws -> VerifiedIdentity`; `VerifiedIdentity` contains issuer/subject only. `CredentialStore.load(registrationID: String) throws -> Credentials?`, `replace(_ credentials: Credentials) throws`, `delete(registrationID: String) throws`. `ChatGPTConnection.connect() async throws`, `accessToken(now: Date) async throws -> String`, `disconnect() async throws`. Inject a URLSession and credential store for tests; do not introduce a general dependency container.

- [ ] Add failing signature/claim tests using synthetic signed tokens: reject tampering, `alg=none`, an unexpected algorithm/key type, missing/unknown `kid`, wrong issuer, wrong audience, expired token, wrong nonce, and a returning subject mismatch. A signature-only success never enables plan usage. Add connection tests proving cancel/termination preserves the previous registration and no half-written token set becomes active.

```swift
@Test func rejectsMalformedIdentityToken() {
    #expect(throws: (any Error).self) {
        try IDTokenValidator().validate("invalid", jwks: Data("{}".utf8),
            clientID: "oaiapp_fixture", nonce: "fixture-nonce", now: Date())
    }
}
```
- [ ] Run `IDTokenValidatorTests` and `ConnectionTests`; confirm failure.
- [ ] Add JOSESwift exactly at verified release 3.0.0 and commit its resolved dependency. Use its JWS/JWK validation APIs for cryptographic verification; enforce an explicit RS256 allowlist initially, rejecting unsupported algorithms. Fetch `https://auth.openai.com/.well-known/jwks.json`; do not follow token-supplied `jku` or `x5u`. On unknown `kid`, refresh the trusted key set once before rejecting. Check issuer `https://auth.openai.com`, audience matching the issued client ID, nonempty subject, expiry, issued-at time, and attempt nonce, allowing at most five seconds of clock skew. If the provider actually requires another signing algorithm, cite its authoritative metadata before changing the allowlist.
- [ ] Exchange codes at the official token endpoint with the issued ID, exact redirect URI, verifier, and resource. Enable plan requests only when required scopes are granted. Keychain stores each `(issuer, subject, issuedClientID)` registration separately using `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; it also stores the stable per-install host ID. Authorization-attempt codes/verifiers are memory-only and abandoned on relaunch.
- [ ] Add a concurrent refresh test: two callers trigger one refresh and receive the same access token; restart loads the new refresh token. Add tests for transient refresh failure preserving credentials, terminal invalid refresh clearing unusable credentials, and logout clearing local credentials even when remote revocation fails. Serialize refresh in an actor, update the credential record atomically, and report revocation as unconfirmed on network failure.
- [ ] Run both suites and commit `feat: validate and protect account sessions`. Never record token strings, email, subjects, raw callback URLs, or raw provider responses in evidence.

### Task 4: Account-specific model discovery and completed image request

**Files:** Create `ResponsesClient.swift` and `ios/MivuTests/ResponsesClientTests.swift`; modify `ConnectionProofView.swift` and `ChatGPTConnection.swift`.

**Interfaces:** `ResponsesClient.models(accessToken: String) async throws -> [AvailableModel]`; `run(model: String, text: String, image: Data?, accessToken: String) async throws -> ProbeResult`. `AvailableModel` has slug/displayName; `ProbeResult` has model and outputText and is constructed only after completed inference. `ResponsesClient(session: URLSession)` accepts a fixture session. The test helper `sessionReturning(status: Int, body: Data) -> URLSession` uses URLProtocol interception and performs no real network traffic.

- [ ] Add failing fixture tests for model discovery, image data-URL input, `store=false`, `stream=true`, and absence of unsupported fields. Feed SSE in arbitrary byte chunks, including split UTF-8; completed output succeeds, but truncation, malformed events, failure events, HTTP 403/429, and errors after HTTP 200 fail without producing a completed result. Verify no request is sent without plan permission.

```swift
@Test func rejectsHttpSuccessWithoutCompletedEvent() async {
    let client = ResponsesClient(session: sessionReturning(status: 200, body: Data()))
    await #expect(throws: (any Error).self) {
        try await client.run(model: "fixture-model", text: "Synthetic test", image: nil, accessToken: "fixture-token")
    }
}
```
- [ ] Run `ResponsesClientTests` and confirm failure.
- [ ] Use URLSession for `GET https://api.openai.com/v1/models` and `POST https://api.openai.com/v1/responses` with the active OAuth bearer token. Select from the returned account catalog rather than assuming a model. Consume the documented response stream; accept only `response.completed`, reject failed/incomplete streams, and retain all input context per request. Keep parsing/transport outside the future diary calculation boundary.
- [ ] Add a built-in synthetic image and short prompt, clearly labeled as a connection test. Let the owner authorize through the app, choose an available compatible model, and run one request. Consent is performed by the owner; never extract credentials from an existing application. Do not retry quota/ineligibility automatically or switch billing.
- [ ] Run the targeted tests successfully. Record live account image access separately from fixtures, showing only sanitized status/model/latency. Commit `feat: add completed synthetic image probe`.

### Task 5: Durable interruption recovery and honest status

**Files:** Create `ProbeJob.swift` and `ios/MivuTests/ProbeJobTests.swift`; modify `ResponsesClient.swift`, `ChatGPTConnection.swift`, and `ConnectionProofView.swift`.

**Interfaces:** `ProbeJob: Codable, Identifiable` holds UUID, synthetic input, selected model, owner registration reference, and `ProbeJobState: Codable` (`pending`, `analyzing`, `needsRetry`, `completed`). `ProbeJobStore(directory: URL)`, `save(_ job: ProbeJob) throws`, `load() throws -> ProbeJob?`, `remove(id: UUID) throws`. Its `load()` returns interrupted `analyzing` work as `pending`. `ProbeRunner.run(_ job: ProbeJob) async throws -> ProbeResult` performs one eligible attempt and checks job identity before completing it.

- [ ] Add failing tests: save failure does not acknowledge capture; restart changes interrupted analyzing work to pending; retry retains its UUID; stale result after deletion cannot restore the job; account switching never uses another registration's credentials. Simulate loss of network/stream, quota, and cancellation; pending inputs survive while partial output does not become a result.

```swift
@Test func interruptedJobRestoresAsPending() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let job = ProbeJob(id: UUID(), text: "Synthetic test", image: nil,
        model: "fixture-model", registrationID: "fixture-registration", state: .analyzing)
    try ProbeJobStore(directory: directory).save(job)
    let restored = try #require(ProbeJobStore(directory: directory).load())
    #expect(restored.id == job.id)
    #expect(restored.state == .pending)
}
```
- [ ] Run `ProbeJobTests` and confirm failure.
- [ ] Store the small synthetic job atomically in protected Application Support files, never credentials. Run one job at a time. On interruption, preserve pending work and resume when foreground/authorized execution is available. Use bounded retry delays of 1, 2, and 4 seconds for transient failures while executing; after exhaustion show Needs retry. Quota/ineligibility/revocation pauses for user action. Show local persistence status independently from inference status.
- [ ] Test real foreground/background/lock transitions and forced relaunch on the owner's phone. Do not claim guaranteed suspended execution; this proof does not require a continued-processing entitlement. Record whether processing completes or safely resumes.
- [ ] Run the suite successfully and commit `feat: recover interrupted connection probes`.

### Task 6: Evidence, integration decision, and review

**Files:** Create the verification report and integration ADR; update `README.md` and the approved spec only with observed findings.

**Interfaces:** A gate result is `PASS`, `FAIL`, or `NOT_RUN_BLOCKED`, with evidence for native callback, validated authorization, image completion, refresh, denial/revocation/quota handling, and physical-device interruption recovery. Simulated failure evidence is labeled separately.

- [ ] Run the aggregate test command, inspect the diff for credentials/generated drift, and review UI states in English/Hebrew, light/dark, large text, VoiceOver, reduced motion, and offline mode. Record pass/fail/skip counts and the exact source commit.
- [ ] Document the callback/eligibility outcome and distribution/signing prerequisites. Check the owner's available backup identity/storage options and current costs without creating resources. The diary plan must select a concrete provider and acknowledgment/deletion semantics; this report must not claim a selection or successful restore before evidence exists.
- [ ] If any required native integration condition fails or cannot be tested, label it explicitly and stop expansion around that route. Keep unrelated repository/documentation work reviewable; do not silently weaken iPhone-only use or substitute another model/provider.
- [ ] If all integration requirements pass, record the narrow success and prepare the next diary/backup implementation plan from the spec. A completed connection proof is not a working food diary or a completed pilot.
- [ ] Commit `docs: record native integration verification`, open a focused draft PR in the approved repository, attach its URL to this chat, and request the selected review method. Avoid a paid CI runner until its included allowance/budget is established. Merge only after required checks/review and repository rules permit it.

## Plan review and execution

Recommend **Native execution**: implement these dependent tasks in this session,
then perform one independent review of the branch. The authentication callback
and credential handling deserve a fresh security review; per-task delegation
adds context cost without removing the shared dependency on the phone proof.

Alternative: **Subagent-driven execution**, with an independent implementer and
reviewer per task, at higher context cost. No agents are dispatched before the
owner selects the execution method.

Approved by the owner on 2026-10-11: native execution, followed by an
independent whole-branch review. Repository destination is `yakov103/mivu`.
Xcode license acceptance remains a separate human gate. No blocked build or
physical-device check may be reported as passed.
