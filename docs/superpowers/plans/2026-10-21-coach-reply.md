# Coach Reply-to-Message Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** WhatsApp-style replies in Coach: quote any message or a Diary record, send it with the turn, show it in the bubble, and give ChatGPT the quoted content.

**Architecture:** One `CoachReply` value lives in the immutable `CoachSubmissionManifest`, so capture, reconciliation, paging, relaunch and archives carry it with no schema change. The processed turn's inference context resolves it to bounded current content. UI adds a composer quote bar, a bubble quote, a native leading swipe action and per-bubble context menus.

**Tech Stack:** Swift 6, SwiftUI in `UIHostingConfiguration` cells of `CoachTimelineTable`, SQLite payloads, Swift Testing / XCTest via XcodeBuildMCP.

**Spec:** [Coach reply design](../specs/2026-10-21-coach-reply-design.md)

## Global Constraints

- Excerpt: non-empty after trimming, ≤ 280 characters.
- Quoted message text and answer: ≤ 1024 bytes each (`coachBoundedText`). Quoted meal detail only if it encodes ≤ 8 KB. Whole context still ≤ 60 KB.
- Nil reply encodes nothing (ordinary requests unchanged byte-for-byte).
- No schema, index or archive-envelope change; older payloads decode with nil.
- Navigation reply never replaces an in-progress draft (text, photos or reply).
- 44-pt targets, Dynamic Type, VoiceOver custom actions, Reduce Motion; Jump-to-latest and the table's accessibility prefix untouched.
- English-only copy: "Replying to Pip", "Replying to you", "From Diary", "Cancel reply", "Reply", "Reply to Pip", "Reply to your message", photo-only excerpt "Photo".

## Review Focus

1. Uncertain send retried after the person cancels the reply: the frozen attempt keeps its original reply, a changed snapshot starts a new identity (Task 2 test `uncertainRetryKeepsFrozenReply`).
2. Quoted message off the resident page or deleted: tap seeks with the existing "unavailable" outcome; context says `unavailable` (Task 3 `unavailableReplyTargetIsExplicit`, Task 4 UI uses `seek`).
3. Profile switch with a reply set: reply cleared with the draft (Task 2 `profileChangeClearsReply`).
4. Huge quoted Pip answer / huge meal: bounded, context still ≤ 60 KB (Task 3 `quotedContentIsBounded`).
5. Swiping a row whose Pip answer is still pending: replies to the person's own message (Task 4 swipe logic, covered by `replyTarget(for:)` unit test in Task 4).

---

### Task 1: Reply value and persistence

**Files:**
- Modify: `ios/Mivu/Coach/CoachModels.swift` (add `CoachReply`; `CoachSubmissionManifest.reply`; `CoachSubmissionPayload.init(..., reply: CoachReply? = nil)` validates and stores it)
- Modify: `ios/Mivu/Coach/CoachTimelineModels.swift` (`CoachExchangeSummary.reply: CoachReply? = nil`)
- Modify: `ios/Mivu/Diary/DiaryDatabaseQueries.swift:201` (summary takes `turn.submissionManifest?.reply`)
- Modify: `ios/Mivu/Diary/DiaryArchive.swift` validate (excerpt bounds)
- Test: `ios/MivuTests/CoachReplyTests.swift` (new)

**Interfaces:**
- Produces: `struct CoachReply: Codable, Equatable, Sendable { enum Target { case message(turnID: UUID, fromPip: Bool), meal(UUID), item(mealID: UUID, itemID: UUID), day(UUID) }; var target: Target; var excerpt: String; var isValid: Bool }`; `CoachExchangeSummary.reply`.

- [ ] Tests: `replyPersistsWithTurnAndPage` (capture payload with `.meal` reply through `DiaryStore.captureCoachSubmission`, new `DiaryStore` on same directory, `coachPage(.latest)` exchange `.reply == reply`); `replyIsPartOfImmutableCapture` (reconcile same submission ID with a manifest whose reply differs → `.conflictingPayload`); `replyExcerptIsBounded` (281-char and whitespace excerpts throw `DiaryError.invalidData`); `archiveRoundTripsReply` (export/import keeps reply).
- [ ] Run, see them fail; implement; run focused `CoachReplyTests` plus `CoachCaptureTransactionTests`, `ArchiveTests`; commit `feat(coach): persist a reply target with each captured turn`.

### Task 2: Draft, view model and navigation request

**Files:**
- Modify: `ios/Mivu/Coach/CoachAttachmentDraft.swift` (`var reply: CoachReply?`; part of `Snapshot`; passed to payload; cleared on accept and ownership change)
- Modify: `ios/Mivu/Coach/CoachViewModel.swift` (`func reply(to turn: CoachExchangeSummary, fromPip: Bool)`, `@discardableResult func startReply(_ reply: CoachReply) -> Bool` — false if text, photos or reply exist)
- Modify: `ios/Mivu/Coach/CoachTimelineModels.swift` (`CoachNavigationRequest.reply: CoachReply? = nil`), `ios/Mivu/Coach/CoachNavigationOwner.swift` (`queue(_:draft:reply:from:...)`, `OpenDiaryCoachAction.callAsFunction(_:draft:reply:expectedSelection:)`), `ios/Mivu/Diary/TodayView.swift` pass-through
- Modify: `ios/Mivu/Coach/CoachView.swift` navigation task applies `startReply` and focuses the field
- Test: `ios/MivuTests/CoachReplyTests.swift`

- [ ] Tests: `sendAttachesReplyAndClears` (draft text + reply, `send()`, accepted summary `.reply` equal, draft reply nil); `uncertainRetryKeepsFrozenReply`; `profileChangeClearsReply`; `queuedReplyReachesRequest`; `navigationReplyNeverReplacesInProgressDraft`; `messageExcerptUsesTextOrPhoto` (reply(to:) on photo-only turn → "Photo"; long text truncated to 280).
- [ ] Implement, run focused `CoachReplyTests`, `CoachAttachmentDraftTests`, `CoachNavigationTests`; commit `feat(coach): reply from the composer and Diary handoffs`.

### Task 3: Inference context

**Files:**
- Modify: `ios/Mivu/Coach/CoachModels.swift` (`CoachContext.Reply { target, excerpt, turn: Turn?, meal: Meal?, unavailable: Bool? }`, `CoachContext.replyTo`)
- Modify: `ios/Mivu/Diary/DiaryDatabaseCoachContext.swift` (`coachInferenceContext` fills `replyTo` from the work turn's manifest; one row read for a message; `coachMealDetail` for meal/item if ≤ 8 KB; meal trimming never drops `replyTo`)
- Modify: `ios/Mivu/Coach/CoachEngine.swift` developer instruction sentence
- Test: `ios/MivuTests/CoachReplyTests.swift`

- [ ] Tests: `inferenceContextCarriesQuotedMessage` (quoted turn older than 12 recent turns still appears with its text and answer); `inferenceContextCarriesQuotedMeal`; `ordinaryTurnContextHasNoReplyKey` (encoded JSON lacks `"replyTo"`); `unavailableReplyTargetIsExplicit`; `quotedContentIsBounded`.
- [ ] Implement, run focused `CoachReplyTests`, `CoachIndexedContextTests`, `CoachEngineTests`; commit `feat(coach): send the replied-to message or record as context`.

### Task 4: Timeline and composer UI

**Files:**
- Create: `ios/Mivu/Coach/CoachReplyQuote.swift` (one SwiftUI view used by bar and bubble; `CoachReply.title`/`fromPip` helpers)
- Modify: `ios/Mivu/Coach/CoachView.swift` (bar above field with ✕, bubble quote button routing: message/day → `coach.seek`, meal/item → `selectedRecord = .meal`; `.contextMenu` with Copy/Reply on both bubbles; `.accessibilityAction(named:)` on the exchange)
- Modify: `ios/Mivu/Coach/CoachTimelineView.swift` (`leadingSwipeActionsConfigurationForRowAt` → "Reply" with `arrowshape.turn.up.left`, `onReply` closure on `CoachTimelineView`)
- Test: `ios/MivuUITests/CoachReplyUITests.swift` (new), `ios/MivuTests/CoachReplyTests.swift` (`swipeRepliesToAnswerOrOwnMessage`)

- [ ] UI tests (fixture `--coach-inference-fixture`): `testSwipeReplyQuotesPipSendsAndQuoteSeeksOriginal` (send two messages, swipe first row right, bar shows "Replying to Pip", send, bubble shows quote, relaunch, quote remains, tap quote highlights first exchange); `testLongPressReplyToOwnMessageAndCancel` (context menu Reply on own bubble shows "Replying to you", ✕ removes bar).
- [ ] Implement; full Coach UI suite + focused units on own simulator; commit `feat(coach): swipe or long-press to reply in the chat`.

### Task 5: Docs, evidence, PR

- [ ] Update `docs/development/coach-chat-behavior.md` (reply section), add `docs/verification/2026-10-21-coach-reply.md` with SHA, simulator, result counts, manual VoiceOver/rotor gaps.
- [ ] Ponytail Review, push, PR against `feat/diary-redesign` titled `feat(coach): reply to a message or Diary record`.
