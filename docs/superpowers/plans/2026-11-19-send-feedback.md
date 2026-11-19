# Send Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native Send feedback screen in Mivu for iOS that sends a bug, idea or question with visible device details, by email now and directly through a Lambda once AWS is unblocked.

**Architecture:** One pure-logic file builds, validates and delivers a report; one SwiftUI form uses it. Settings pushes the form; Coach reaches it through the existing Settings handoff and through a sheet on a failed turn. A single Info.plist value decides the delivery path: empty means the prefilled email, a URL means a direct POST. The server is one Python function that validates the same fields and forwards the report through SES.

**Tech Stack:** Swift, SwiftUI `Form`, `URLSession`, Swift Testing, XCUITest, `Localizable.xcstrings`; Python 3.12 standard library plus `boto3` (already in the Lambda runtime), `unittest`.

**Spec:** `docs/superpowers/specs/2026-11-19-send-feedback-design.md`. The spec file is untracked on another branch; Task 1 copies it and this plan into the feature branch.

> **Amended 2026-11-19:** Tasks 4 and 5 were re-scoped by an owner decision. The server is a `POST /feedback` route on the existing worker in `mivu-infra` (branch `feat/feedback-route`), not a Lambda; Task 3 does not add a `CoachDestination` case. The spec's Amendments section is the authority.

## Global Constraints

- Branch `feat/send-feedback` from `origin/main` (`0fcceeee` or newer), in its own worktree. Never build on `codex/mivu-icon-wordmark`.
- Follow `AGENTS.md`: failing test first, minimal Swift, platform APIs, Dynamic Type, VoiceOver, reduced motion, 44-point targets.
- iOS only. Do not touch `android/`.
- A report contains exactly: `kind`, `message`, optional `email`, `appVersion`, `build`, `os`, `device`, `language`, optional `context`. Never diary data, chat text or the raw `failureReason`.
- `kind` is `bug`, `idea` or `question`. `context` is `coach_network`, `coach_session` or `coach_other`.
- `message`: trimmed, 1 to 4,000 characters. `email`: optional, at most 254 characters, no whitespace.
- Support address: `support@mivuapp.com`.
- The screen says a report was sent only after the server answered HTTP 204.
- Nothing logs the message or the email address, in the app or the function.
- New user-facing strings get English, Spanish and Russian entries in `ios/Mivu/Localizable.xcstrings`.
- Tests use synthetic input and never call a real endpoint or AWS.
- Run only the named focused tests with XcodeBuildMCP (scheme `Mivu`); record the tested SHA. No full UI suite.
- Commit and PR text: Conventional Commits, no mention of assistants or tools, no co-author lines.
- Do not deploy to AWS, change the App Store listing, or upload a build. Task 5 is gated on the owner.
- The Xcode project uses synchronized folders: new files under `ios/Mivu`, `ios/MivuTests` and `ios/MivuUITests` need no project edits.

## Review Focus

1. **Header-like text in the email field** (`a@b.co\nBcc: x@y.z`): rejected in the app and by the function; never reaches an email header. Tests in Tasks 1 and 4.
2. **A 200 response that is not ours** (hotel Wi-Fi login page): treated as a failure, since only 204 counts. Test in Task 1.
3. **Double tap on Send:** one request; the button is disabled while sending. Test in Task 2.
4. **Pasting far more than 4,000 characters:** Send is disabled and a count is shown; the text is never cut silently. Tests in Tasks 1 and 2.
5. **No mail app can open the email link:** the screen shows the support address as selectable text instead of doing nothing. Test in Task 2.

---

### Task 1: Report model, validation and delivery

**Files:**
- Create: `ios/Mivu/Feedback/Feedback.swift`
- Create: `ios/MivuTests/FeedbackTests.swift`
- Modify: `ios/Config/Info.plist` (add `MivuFeedbackEndpoint` = `$(MIVU_FEEDBACK_ENDPOINT)`)
- Modify: `ios/Config/Shared.xcconfig` (add `MIVU_FEEDBACK_ENDPOINT =` with an empty value)
- Add to the branch: the spec and this plan

**Interfaces:**
- Produces:

```swift
enum FeedbackKind: String, Codable, CaseIterable, Sendable { case bug, idea, question }
enum FeedbackContext: String, Codable, Sendable {
    case coachNetwork = "coach_network", coachSession = "coach_session", coachOther = "coach_other"
    init(_ state: CoachTurnState)   // waitingForNetwork -> coachNetwork, waitingForConnection -> coachSession, else coachOther
}
struct FeedbackDiagnostics: Equatable, Sendable {
    var appVersion, build, os, device, language: String
    static var current: FeedbackDiagnostics   // bundle short version, bundle version, UIDevice systemVersion, utsname machine, Bundle.main.preferredLocalizations.first ?? "en"
}
struct FeedbackReport: Encodable, Equatable, Sendable {
    var kind: FeedbackKind; var message: String; var email: String?
    var appVersion, build, os, device, language: String
    var context: FeedbackContext?
    /// Trims message and email; an empty email becomes nil. Returns nil when the message or email is invalid.
    init?(kind: FeedbackKind, message: String, email: String, diagnostics: FeedbackDiagnostics, context: FeedbackContext?)
    /// The lines shown under "Included with your report" and appended to the email body.
    var includedLines: [String]
}
enum Feedback {
    static let messageLimit = 4000
    static var endpoint: URL?          // Info.plist MivuFeedbackEndpoint; nil when empty or not https
    static func mailto(_ report: FeedbackReport) -> URL
    static func send(_ report: FeedbackReport, to endpoint: URL, session: URLSession = .shared) async throws
}
enum FeedbackError: Error { case rejected }
```

- [ ] **Step 1: Create the worktree and branch**, copy the spec and this plan in, commit as `docs(feedback): add design and plan`.

- [ ] **Step 2: Write the failing tests** in `FeedbackTests.swift` (Swift Testing, `@testable import Mivu`). Use `let d = FeedbackDiagnostics(appVersion: "1.7.0", build: "42", os: "26.1", device: "iPhone17,1", language: "es")`. Stub the network with a `URLProtocol` subclass on an ephemeral `URLSession`.

```swift
@Test func trimsAndBuilds() {
    let r = FeedbackReport(kind: .bug, message: "  It broke \n", email: " a@b.co ", diagnostics: d, context: .coachNetwork)
    #expect(r?.message == "It broke"); #expect(r?.email == "a@b.co"); #expect(r?.language == "es")
}
@Test func emptyEmailIsNil() { #expect(FeedbackReport(kind: .idea, message: "x", email: "  ", diagnostics: d, context: nil)?.email == nil) }
@Test(arguments: ["", "   ", String(repeating: "a", count: 4001)])
func rejectsMessage(_ m: String) { #expect(FeedbackReport(kind: .bug, message: m, email: "", diagnostics: d, context: nil) == nil) }
@Test func acceptsLimit() { #expect(FeedbackReport(kind: .bug, message: String(repeating: "a", count: 4000), email: "", diagnostics: d, context: nil) != nil) }
@Test(arguments: ["nope", "a@b", "a b@c.co", "a@b.co\nBcc: x@y.z", String(repeating: "a", count: 250) + "@b.co"])
func rejectsEmail(_ e: String) { #expect(FeedbackReport(kind: .bug, message: "x", email: e, diagnostics: d, context: nil) == nil) }
@Test func jsonHasExactlyTheAgreedFields() throws   // encode a full report; keys == ["kind","message","email","appVersion","build","os","device","language","context"]; context == "coach_network"
@Test func jsonOmitsNilEmailAndContext() throws
@Test func includedLinesListEverythingSent()         // contains "1.7.0", "42", "26.1", "iPhone17,1", "es", and "coach_network" only when context is set
@Test func mailtoCarriesTheSameReport()              // scheme mailto, path support@mivuapp.com, subject starts "[Bug] Mivu 1.7.0 (42)", body contains the message and every includedLines entry, and does not contain the email field value
@Test func contextFromTurnState()                    // .waitingForNetwork -> .coachNetwork, .waitingForConnection -> .coachSession, .needsRetry -> .coachOther
@Test func sendPostsJSONAndAccepts204() async throws // stub records method POST, Content-Type application/json, body decodes to the report
@Test(arguments: [200, 400, 413, 500])
func sendThrowsOnAnythingBut204(_ status: Int) async // #expect(throws: FeedbackError.rejected)
@Test func sendThrowsWhenOffline() async             // stub fails with URLError(.notConnectedToInternet); error is rethrown
```

- [ ] **Step 3: Run `MivuTests/FeedbackTests`.** Expected: build fails, `FeedbackReport` not found.

- [ ] **Step 4: Implement `Feedback.swift`** to the interface above. Email rule: at most 254 characters and matches `^[^@\s]+@[^@\s]+\.[^@\s]+$`. `send` uses a 15-second request timeout. `mailto` follows `MivuLinks.reportReply` in `ios/Mivu/Connection/OpenAIConsent.swift`. In `Shared.xcconfig` leave the value empty and add the one-line comment `// A URL here must be written https:/$()/host/path, because // starts a comment.`

- [ ] **Step 5: Run `MivuTests/FeedbackTests`.** Expected: all pass.

- [ ] **Step 6: Commit** `feat(feedback): add report model and delivery`.

---

### Task 2: Feedback screen and Settings row

**Files:**
- Create: `ios/Mivu/Feedback/FeedbackView.swift`
- Modify: `ios/Mivu/Diary/SettingsView.swift` (`SettingsSection` near line 30, Support section near line 71, `settingsDetail`, `title(_:)` near line 387)
- Modify: `ios/Mivu/Localizable.xcstrings`
- Create: `ios/MivuUITests/FeedbackUITests.swift`
- Modify: `ios/MivuTests/FeedbackTests.swift`

**Interfaces:**
- Consumes: everything Task 1 produces.
- Produces:

```swift
struct FeedbackView: View {
    init(kind: FeedbackKind = .bug, context: FeedbackContext? = nil,
         endpoint: URL? = Feedback.endpoint, diagnostics: FeedbackDiagnostics = .current,
         send: @escaping (FeedbackReport, URL) async throws -> Void = { try await Feedback.send($0, to: $1) })
}
@MainActor @Observable final class FeedbackForm {
    var kind: FeedbackKind; var message = ""; var email = ""
    private(set) var phase: Phase          // .editing, .sending, .failed, .sent, .mailUnavailable
    enum Phase: Equatable { case editing, sending, failed, sent, mailUnavailable }
    var report: FeedbackReport?            // nil while the fields are invalid
    var canSend: Bool                      // report != nil && phase != .sending
    var overLimit: Bool                    // trimmed message longer than 4,000
    func submit(openMail: (URL) async -> Bool) async   // direct when endpoint != nil, else mail
    func sendByEmail(openMail: (URL) async -> Bool) async
}
```
- `SettingsSection` gains `case feedback`.

**Screen content, top to bottom:**
- Segmented picker: Bug, Idea, Question. Identifier `feedbackKind`.
- Message editor, at least 5 lines tall. Placeholder by kind: "What happened, and what did you expect?" / "What would make Mivu better?" / "What would you like to know?". Identifier `feedbackMessage`. A character count appears only above 3,600 characters and turns `Color.diaryError` above 4,000.
- Email field, `.emailAddress` content type and keyboard, no autocapitalization. Label "Email (optional)". Footer "Add it if you'd like a reply." Identifier `feedbackEmail`.
- Section "Included with your report" listing `report.includedLines`, or the diagnostics alone while the form is invalid. Footer "Your diary is never included." Identifier `feedbackIncluded`.
- Primary button, identifier `feedbackSend`: "Send" when an endpoint is configured, "Send by email" when not.
- `.failed`: text "Couldn't send. Check your connection and try again." (identifier `feedbackError`), the primary button reads "Try Again", and a "Send by email instead" button appears (identifier `feedbackEmailFallback`).
- `.mailUnavailable`: selectable text "Email us at support@mivuapp.com" (identifier `feedbackAddress`).
- `.sent`: "Thanks! Your report is on its way." with a success haptic, then dismiss after 1.5 seconds; no delay animation under reduced motion beyond the text.
- Settings row: `settingsRow(String(localized: "Send feedback"), symbol: "bubble.left.and.exclamationmark.bubble.right", color: .diaryProtein)` as a `NavigationLink(value: SettingsSection.feedback)`, placed directly above the Privacy Policy row, identifier `sendFeedback`. Navigation title "Send feedback".

- [ ] **Step 1: Write the failing form tests** (append to `FeedbackTests.swift`; build `FeedbackForm` with injected `endpoint`, `diagnostics`, `send`).

```swift
@Test func directSendReachesSentOnlyAfterSuccess() async      // send closure succeeds -> phase == .sent; openMail never called
@Test func failureKeepsTextAndOffersRetry() async             // send throws -> phase == .failed; message and email unchanged; canSend true
@Test func retryAfterFailureCanSucceed() async
@Test func emailFallbackOpensTheSameReport() async            // after .failed, sendByEmail passes Feedback.mailto(report) to openMail
@Test func noEndpointUsesMailAndNeverClaimsSent() async       // endpoint nil -> openMail called; phase stays .editing; send closure never called
@Test func mailUnavailableShowsAddress() async                // openMail returns false -> phase == .mailUnavailable
@Test func secondSubmitWhileSendingIsIgnored() async          // hold the send closure with a continuation; call submit twice; closure ran once
@Test func overLimitDisablesSend()                            // 4,001 characters -> canSend false, overLimit true; message.count still 4,001
```

- [ ] **Step 2: Write the failing UI test** `FeedbackUITests.testSettingsOpensFeedbackForm`, launching the way `ios/MivuUITests/DiaryUITests.swift` does: open Settings, tap `sendFeedback`; assert `feedbackKind`, `feedbackMessage`, `feedbackEmail` and `feedbackIncluded` exist; assert `feedbackSend` is disabled; type "Synthetic test message" into `feedbackMessage`; assert `feedbackSend` is enabled. Do not tap Send.

- [ ] **Step 3: Run `MivuTests/FeedbackTests` and `MivuUITests/FeedbackUITests`.** Expected: build fails, `FeedbackForm` not found.

- [ ] **Step 4: Implement `FeedbackForm` and `FeedbackView`**, then the Settings row, `SettingsSection.feedback`, its `settingsDetail` branch and `title(_:)` case. The view passes `{ await openURL($0) }` style mail opening through `@Environment(\.openURL)` and its completion result. Use the app's existing `Color.diary*` tokens and `settingsRow` so the screen matches Settings.

- [ ] **Step 5: Add the strings** to `Localizable.xcstrings` with `es` and `ru` translations for every new string above.

- [ ] **Step 6: Run both test targets from Step 3.** Expected: all pass.

- [ ] **Step 7: Capture screenshots** on the simulator through the T3 device tools: default size light, dark, and the largest accessibility text size; one in Spanish. Save under `docs/verification/feedback/`.

- [ ] **Step 8: Commit** `feat(feedback): add send feedback screen to settings`.

---

### Task 3: Coach entry points

**Files:**
- Modify: `ios/Mivu/Coach/CoachModels.swift:7` (`CoachDestination`)
- Modify: `ios/Mivu/Coach/CoachManualEdits.swift:86` (`open_settings` description)
- Modify: `ios/Mivu/Coach/CoachView.swift` (failed-turn buttons near lines 441 and 977, `linkTitle` near 1075, link icon near 1052)
- Modify: `ios/Mivu/Diary/SettingsView.swift:397` (`open(_:)`)
- Modify: `ios/Mivu/Localizable.xcstrings`
- Modify: `ios/MivuTests/CoachManualEngineTests.swift`, `ios/MivuTests/FeedbackTests.swift`
- Possibly modify: `ios/MivuTests/ArchiveFixtureTests.swift` and its fixture, which iterate `CoachDestination.allCases`

**Interfaces:**
- Consumes: `FeedbackView(kind:context:)`, `FeedbackContext(_ state:)`.
- Produces: `CoachDestination.feedback` (raw value `feedback`).

- [ ] **Step 1: Write the failing tests.**

```swift
// CoachManualEngineTests, beside the existing open_settings test at line 126
@Test func openSettingsAcceptsFeedbackDestination() async throws   // call("open_settings", ["destination": "feedback"]) yields a receipt whose destination == .feedback
// FeedbackTests
@Test func olderStoredDestinationsStillDecode() throws             // JSONDecoder decodes "settings","profiles","connection","nutritionSource","backup" as CoachDestination
@Test func feedbackToolTextNeverClaimsSending()                    // the open_settings description contains "feedback" and "never sends"
```

- [ ] **Step 2: Run `MivuTests/CoachManualEngineTests`, `MivuTests/FeedbackTests` and `MivuTests/ArchiveFixtureTests`.** Expected: the new tests fail; note whether the archive fixture test fails once the case exists.

- [ ] **Step 3: Implement.**
  - Add `feedback` as the last `CoachDestination` case.
  - Append to the `open_settings` description: " Use destination feedback when the person wants to report a bug, suggest a feature or contact the team; the app shows a form and this tool never sends a report."
  - `linkTitle`: `.feedback` returns `String(localized: "Send feedback")`; that link uses the icon `bubble.left.and.exclamationmark.bubble.right` instead of `gearshape`.
  - `SettingsView.open(_:)`: `.feedback` sets `linkedSection = .feedback`.
  - Beside each of the two "Try again" buttons, add `Button("Report this problem")` (identifier `coachReportProblem`, 44-point minimum) that presents `FeedbackView(kind: .bug, context: FeedbackContext(turn.state))` in a sheet inside a `NavigationStack` with a Cancel button. Show it only where "Try again" shows, and for the list row only when `turn.state == .needsRetry`, `.waitingForNetwork` or `.waitingForConnection` (not `.needsClarification`).
  - If `ArchiveFixtureTests` fails, regenerate its fixture the way that test file documents; do not hand-edit expected bytes.

- [ ] **Step 4: Add the strings** ("Report this problem", "Send feedback" link title if not already present) with `es` and `ru`.

- [ ] **Step 5: Run the three test classes from Step 2.** Expected: all pass.

- [ ] **Step 6: Commit** `feat(coach): link to feedback from failures and on request`.

---

### Task 4: Server function (written and tested, not deployed)

**Files:**
- Create: `server/feedback/handler.py`
- Create: `server/feedback/test_handler.py`
- Create: `server/feedback/README.md`

**Interfaces:**
- Consumes: the JSON body Task 1's `FeedbackReport` encodes.
- Produces: `handler.handler(event, context, ses=None) -> dict` for a Lambda function URL event. Responses: 204 accepted, 400 invalid, 405 not POST, 413 body over 16,384 bytes, 502 when SES fails. Empty body in every case.

**Email built by the function:**
- From `feedback@mivuapp.com`, To `support@mivuapp.com`.
- Subject `[Bug] Mivu 1.7.0 (42), iOS 26.1` (kind capitalized).
- Reply-To set only when `email` passed validation.
- Plain-text body: the message, a blank line, `---`, then `Device`, `Language`, `Context` (when present) and `Reply to` (when present), one per line.

- [ ] **Step 1: Write the failing tests** in `test_handler.py` with `unittest` and a fake `ses` object that records `send_email` keyword arguments. A helper `event(body, method="POST")` builds a function-URL event.

```python
def test_accepts_valid_report(self)            # 204; one send; Destination ToAddresses == ["support@mivuapp.com"]; ReplyToAddresses == ["a@b.co"]; subject == "[Bug] Mivu 1.7.0 (42), iOS 26.1"
def test_no_reply_to_without_email(self)       # ReplyToAddresses absent or empty
def test_rejects_non_post(self)                # 405, no send
def test_rejects_oversized_body(self)          # 16,385 bytes -> 413, no send
def test_rejects_bad_json(self)                # 400
def test_rejects_unknown_field(self)           # extra key "diary" -> 400
def test_rejects_missing_or_wrong_type(self)   # each required field missing, and message as a number -> 400
def test_rejects_bad_values(self)              # kind "spam"; empty message; 4,001-char message; context "raw error text"; appVersion over 32 chars -> 400
def test_rejects_header_injection(self)        # email "a@b.co\r\nBcc: x@y.z" -> 400; appVersion "1\r\nBcc: x@y.z" -> 400; no send
def test_message_newlines_stay_in_body(self)   # message "a\r\nSubject: x" -> 204; subject unchanged; text is in the body only
def test_decodes_base64_body(self)             # isBase64Encoded true -> 204
def test_ses_failure_is_502(self)              # fake raises -> 502
def test_never_logs_message_or_email(self)     # assertNoLogs / captured stdout contains neither
```

- [ ] **Step 2: Run** `python3 -m unittest discover -s server/feedback -v`. Expected: import error, `handler` not found.

- [ ] **Step 3: Implement `handler.py`.** Standard library plus a lazily created `boto3.client("sesv2")` when `ses` is None. Field rules: the Global Constraints, plus `appVersion`, `build`, `os`, `device`, `language` each 1 to 32 printable ASCII characters with no control characters. Use SES `Simple` content so SES builds the headers.

- [ ] **Step 4: Run the tests again.** Expected: all pass.

- [ ] **Step 5: Write `README.md`**: what the function does, the request contract, how to run the tests, and the deploy steps for Task 5 as commands with a `REGION` placeholder (create an execution role allowing only `ses:SendEmail` from `feedback@mivuapp.com` and basic logging; `python3.12` runtime; 128 MB; 5-second timeout; reserved concurrency 2; function URL with auth type `NONE`; log retention 14 days). State at the top: "Not deployed. Lambda and SES are blocked by organization policy p-il73h2vb as of 2026-11-19."

- [ ] **Step 6: Commit** `feat(feedback): add report forwarding function`.

---

### Task 5: Switch on direct sending (owner-gated; do not start until the owner confirms AWS is unblocked)

**Files:**
- Modify: `ios/Config/Shared.xcconfig` (`MIVU_FEEDBACK_ENDPOINT`)
- Modify: `ios/Mivu/PrivacyInfo.xcprivacy` (locate with `git ls-files '*PrivacyInfo.xcprivacy'`)
- Modify: `docs/development/app-store-submission.md`
- Modify: `server/feedback/README.md`
- Create: `docs/verification/2026-11-19-send-feedback.md`

- [ ] **Step 1: Confirm with the owner** which region is unblocked and that `mivuapp.com` is verified in SES there. Run `aws sts get-caller-identity --profile mivu` and stop unless the account is `582169340364`.
- [ ] **Step 2: Deploy** with the README commands. Ask the owner before creating each resource.
- [ ] **Step 3: Verify the live function** with `curl`: a synthetic valid report returns 204 and arrives at `support@mivuapp.com` (owner confirms receipt and that Reply works); a body with an extra field returns 400; a GET returns 405.
- [ ] **Step 4: Set `MIVU_FEEDBACK_ENDPOINT`** to the function URL in the `https:/$()/` form. Build, send one synthetic report from the simulator, owner confirms receipt.
- [ ] **Step 5: Privacy.** Add collected-data entries to `PrivacyInfo.xcprivacy`: email address and other user content, both for app functionality, not linked to identity beyond the address itself, not used for tracking. Draft for the owner: the privacy-policy paragraph for the private `mivu-site` repo and the matching App Store privacy label answers. Record both drafts in `docs/development/app-store-submission.md`. The owner publishes the policy and edits the label.
- [ ] **Step 6: Write the verification record**: source SHA, simulator and OS, test classes and counts, function region and URL, the observed `curl` results, what the owner confirmed.
- [ ] **Step 7: Commit** `feat(feedback): send reports directly`.

---

### Task 6: Review and pull request (after Task 4; Task 5 is a later PR)

- [ ] **Step 1:** Run `MivuTests/FeedbackTests`, `MivuTests/CoachManualEngineTests`, `MivuTests/ArchiveFixtureTests`, `MivuUITests/FeedbackUITests` and `python3 -m unittest discover -s server/feedback` on the final commit. Record the SHA and counts.
- [ ] **Step 2:** Dispatch the `ux-ui-reviewer` subagent on the Task 2 screenshots plus one of the failed-turn sheet, and the `senior-qa` subagent to use the feature on a simulator. Fix blocking findings.
- [ ] **Step 3:** Run Ponytail Review on the branch diff. Fix blocking findings.
- [ ] **Step 4:** Open a PR to `main` titled `feat(feedback): send feedback screen`. In the body: what ships (email delivery), what is not yet live (direct sending, blocked on AWS policy), the test evidence, and that Android follows separately. Link the PR in the thread.
