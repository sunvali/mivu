# ADR 0001: Native integration and current proof boundary

- **Date:** 2026-10-11
- **Status:** Accepted for the current proof boundary; live authorization and
  product expansion remain gated.

## Context

Mivu's approved design requires native iPhone use and authorization through the
owner's own ChatGPT plan. Before diary implementation, the first milestone is
to establish that the documented connection can work in a native app. The
synthetic callback and response parsing have simulator/fixture evidence, but
real provider consent and inference have not occurred.

## Decision

Keep the native Swift implementation and the official authorization/model
contract as the only route under evaluation. The synthetic
`ASWebAuthenticationSession` to HTTP loopback callback passed synthetically on
the iOS 27.0 iPhone 18 Pro simulator. The final aggregate on source commit
`2f98f7c34741ef744b6fcdac9acc0ea9e0f39807` reported 117 passed, 0 failed, and
1 opt-in browser-test skip across 9 suites; the separate native browser smoke
passed 7/7. The smoke used only a synthetic callback and did not sign in. The
live HTTPS authorization-to-HTTP loopback sequence remains unproven. Whole-
branch findings were fixed and accepted in scoped review; the AuthSession
logout deletion-retry fix was also accepted. This evidence does not establish
live eligibility, owner consent, provider token lifecycle, model compatibility,
or image inference.

The system reports that HTTP callback support is deprecated and may be removed
in a future iOS version. The documented flow uses HTTPS authorization and an
HTTP loopback redirect; a live authorization-to-redirect sequence has not been
proven. Keep the currently authorized sign-in implementation and record this
as a future compatibility risk. Do not silently replace the documented
redirect or use a paid API/model fallback.

Account lifecycle and durable recovery have implementations and scoped test
evidence, and the current app composition passed the final aggregate. Real
owner sign-in and consent, scoped plan permission, live image inference, and
physical-phone interruption/recovery proof require the owner to perform the
actual human authorization/device steps and remain `NOT_RUN_BLOCKED`. Full
scrolling, VoiceOver, and reduced-motion interaction were not verified. The
first proof is not a meal diary; do not claim diary functionality, completed
live proof, or a working backup.

## Backup and distribution

No backup provider is selected. Read-only research checked 2026-10-11 lists
Apple Developer Program membership at USD 99 per year, subject to local
currency, and says CloudKit private database data counts against each user's
iCloud quota. The owner’s membership and available quota are unknown; no
resources or billing were created. Storage, retention, deletion, export, and
restore semantics require a later explicit decision and evidence.

## Consequences

The callback result is narrow and platform-specific. The HTTP deprecation is a
future compatibility risk. Fixture and simulator evidence can guide the next
proof steps but cannot prove the live account flow or establish production
readiness. Diary implementation, backup selection, and publication remain
outside this milestone.
