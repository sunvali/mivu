# Coach reply-to-message verification

Source revision: `875bdf7b04afe45d8acd0e108269dfdf15ac1afa` (branch `feat/coach-reply`,
stacked on `feat/diary-redesign` @ `bf35b30`). This record is the only change after it.
Environment: macOS 27.0.1, Xcode 27.0, iOS 27.0 simulator "iPhone 17 Pro" created for
this work only (`C6FFAE69-…`, baseline on `AE1C61BE-…`), XcodeBuildMCP, test plan `Mivu`.

## Focused tests (all passing at the source revision)

| Suite | Tests |
|---|---|
| `MivuTests/CoachReplyTests` | persistence + relaunch paging, immutable manifest reconciliation, excerpt bounds, archive round-trip/rejection |
| `MivuTests/CoachReplyComposerTests` | send attaches and clears, uncertain retry keeps frozen reply, profile change clears, request carries reply, Diary handoff never replaces a draft, excerpt from text/photo, reply ignored while sending |
| `MivuTests/CoachReplyContextTests` | quoted message outside 12 recent turns, quoted meal/item, ordinary context has no `replyTo`, unavailable targets (4 kinds), bounded quoted content |
| `MivuUITests/CoachReplyUITests` | real swipe → composer quote → send → bubble quote survives relaunch → tap highlights original; long-press Reply on own message, 44-pt cancel |

## Full plan run at the source revision

`/tmp/mivu-reply-final.xcresult`: **1110 passed, 14 failed, 1 skipped** (4512 s).

- 12 failures reproduce on the unchanged base `bf35b30` (`/tmp/mivu-reply-baseline.xcresult`,
  12 failed / 2 passed of the same 14): Diary/Progress/SummaryCards/ManualNutrition/
  DiaryAmountEditor screens being redesigned on the base branch, plus
  `CompanionUITests` composer-height and `CoachUITests/testLargestDynamicTypeDarkCoach…`.
  They are not caused by this change and are not counted as passing.
- 2 failed only in the full run and passed when rerun alone at the same revision
  (`/tmp/mivu-reply-two.xcresult`, 2/2): `CoachCorrectionUITests/testCrashAfterActualCommit…`
  (inference-boundary timeout) and `CoachUITests/testOfflineTextPhotoCapture…`. Treated as
  load-sensitive timing; noted, not claimed as fixed.

## Not verified

- VoiceOver on device: the "Reply" action on each message, the spoken quote label and the
  quote button hint were checked in source and by element labels, not by a person using
  VoiceOver. Rotor action invocation remains a manual check.
- Swipe feel (resistance, haptic, spring) on hardware; simulator only.
- Live ChatGPT behaviour with `replyTo`; tests use the native inference fixture only.
- Diary "Ask Pip" buttons do not exist yet on the base branch; the request field and composer
  behaviour are unit-tested, the end-to-end tap is not.
