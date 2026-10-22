# Apple Intelligence Default Coach Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Logging and Coach work without any account. Apple's Private Cloud Compute model is the default; a connected ChatGPT plan stays optional and wins when present.

**Architecture:** No provider protocol. `CoachEngine.infer` and `ChatGPTConnection.inference()` are already closures of type `([CoachInferenceInput], Data?) async throws -> CoachInferenceResult`. Add one Apple-backed closure of the same type; `CoachEngine`, `CoachTools`, write validation, receipts and onboarding parsing stay unchanged.

**Tech Stack:** Swift 6, FoundationModels (`PrivateCloudComputeLanguageModel`, iOS 27 SDK), Swift Testing, XcodeBuildMCP. Deployment target stays iOS 26.0; the Apple path is `@available(iOS 27, *)`. No new dependency, service, key or billing.

## Decisions (owner, 2026-10-22)

1. Driver: accountless app, not an App Review workaround.
2. Model: on-device `SystemLanguageModel` now (revised 2026-10-22). `PrivateCloudComputeLanguageModel` (32K) needs the managed `com.apple.developer.private-cloud-compute` entitlement; without it every call fails with `ModelManagerError 1046` while `availability` still reports available (observed on macOS 27). The owner has a paid membership and may request the entitlement; `AppleInference.respond` already takes any `LanguageModel`. Measured on-device context is 8,192 tokens; Coach stable rules are 833 and tool descriptions 867 (schemas excluded).
3. Tool loop: adapter closure. `CoachEngine` keeps ownership of the loop and batch validation; Apple tools only capture calls.
4. Accuracy gate: ~12 synthetic text meals + ~4 rendered food images, run once locally. Pass: median kcal error ≤ 20% and every turn logs or asks. No ChatGPT side-by-side.
5. Selection: connected and authorized ChatGPT wins; otherwise Apple. No new setting.
6. Delivery: one PR.

## Adapter design (verified against the iOS 27 SDK interface)

- Map `CoachInferenceInput` to `Transcript`:
  - developer `.message` → `.instructions` with the tool definitions;
  - user `.message` → `.prompt` with text and `.attachment(.image(ImageAttachment(cgImage)))` segments;
  - `.priorOutput` JSON (`function_call`, `message`) → `.toolCalls` / `.response`;
  - `.functionOutput` → `.toolOutput`.
- The Apple closure emits `outputItems` in the same JSON item shape that `CoachInferenceInput.priorOutput` already validates, so `CoachEngine` replays both providers identically.
- Tool schemas: `CoachTools.declarations()` JSON → `GenerationSchema` through its `Codable` conformance (Task 1 proves or replaces this).
- Each capture tool's `call()` reads the whole parallel batch from `session.transcript.last` while it runs, then throws a private sentinel. A throw rolls the transcript back, so it cannot be read afterwards (observed live).
- Only the first developer message becomes instructions; the per-turn context developer message joins the captured prompt.
- Every `respond` overload requires a prompt. After tool outputs, the rebuilt transcript ends with `.toolOutput` and the adapter sends a fixed continuation prompt. Record this as `shortcut:` until an API that resumes without a prompt exists.
- Error mapping onto existing turn states:
  - `quotaLimitReached` → `ResponsesClient.Failure.quotaReached`;
  - `networkFailure` / `serviceUnavailable` → transient (`waitingForNetwork`);
  - model unavailable → `SessionError.noActiveSession` (`waitingForConnection`) with Apple-specific copy.

## Tasks

### Task 1: Tool schema bridge
- [x] Failing test in `ios/MivuTests/AppleInferenceTests.swift`: every tool in `CoachTools.declarations()` converts to a `Transcript.ToolDefinition` with the same name and a decodable `GenerationSchema`.
- [x] Implement `AppleInference.toolDefinitions(_ namespace: Data)`. Finding: the `Codable` format is Apple's own dialect (objects need `title` and `x-order`, single-string `type`, optional by omission from `required`), so the bridge rewrites the strict schema; integer enums are dropped by the decoder and stay enforced by `CoachTools.parse`.
- Run tests on an iOS 27 simulator; on iOS 26.5 the suite records "requires iOS 27".

### Task 2: Transcript mapping
- [x] Failing test: a developer message, a user message with one JPEG, a prior `function_call` item and its `function_call_output` map to instructions, prompt (text + image), toolCalls and toolOutput entries in order.
- [x] Implement `AppleInference.transcript(_ input: [CoachInferenceInput], tools:)`. Contiguous user chunks merge into one prompt; ChatGPT reasoning items are skipped.

### Task 3: Result capture
- [x] Failing test: two captured calls yield matching `CoachToolCall`s whose `outputItems` replay as the same `.toolCalls`; text yields a replayable `.response`.
- [x] Implement `AppleInference.result` and the capture tool.

### Task 4: Live closure and errors
- [x] Implement `AppleInference.respond` with the continuation prompt (live probe: two parallel lookups captured, continuation then produced one `log_food`, ~1.3 s per step on-device).
- [ ] Map on-device `GenerationError`s (context window, rate limit, guardrail) onto existing turn states; today they fall through to `needsRetry`.

### Task 5: Selection and scheduling
- [x] Failing test: without a plan, an available Apple model makes `canInfer` true and `inference()` return the Apple closure; unavailable still throws `noActiveSession`.
- [x] `ChatGPTConnection.inference()` chooses; `canInfer` replaces `planAuthorized` in Coach scheduling, the Coach connect banner and onboarding. Tests for the no-provider path pin `appleModelAvailable: { false }`.

### Task 6: Accuracy gate
- [ ] Add synthetic meals with reference kcal/macros under `ios/MivuTests` fixtures; a local-only test runs them through the Apple closure when PCC is available and skips otherwise.
- [ ] Record results, device/OS, source SHA and pass/fail in `docs/verification/2026-10-22-apple-default-coach.md`. If the gate fails, stop and report before Task 7.

### Task 7: Copy and docs
- [ ] Coach empty state, onboarding, Settings connection section and failure copy stop assuming ChatGPT; OpenAI consent appears only when connecting ChatGPT.
- [ ] Privacy text and `docs/development/app-store-submission.md`: requests go to Apple Private Cloud Compute (not "never leaves the device"); no account needed.

### Task 8: Verify and ship
- [ ] Focused unit tests plus full local UI verification for changed screens via XcodeBuildMCP; record the SHA and result bundle.
- [ ] Ponytail Review, conventional-commit PR, CI.

## Risks

- PCC eligibility, quota size and device coverage are unverified; the gate run is the first evidence.
- The continuation prompt may change model behaviour after tool outputs; Task 6 covers it.
- iOS 26 users without ChatGPT get a clear unavailable state, not a working Coach.
