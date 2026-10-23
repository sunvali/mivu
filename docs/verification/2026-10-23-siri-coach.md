# Siri to Coach: verification

- Design: [2026-10-23-siri-coach-design.md](../superpowers/specs/2026-10-23-siri-coach-design.md)
- Plan: [2026-10-23-siri-coach.md](../superpowers/plans/2026-10-23-siri-coach.md)
- Tested source: `fcb33befea67a0ae16c1145f56a422a1451e1937` (branch `feat/siri-coach`, based on `main` f66b8896)
- Environment: macOS 27.0.1, Xcode 27.0 (27A266a), iOS 26.5 simulator "iPhone 17 Pro Max"
  (B9200870-53EE-4EEB-B429-3EBDA5E1E93B), `xcodebuildmcp simulator test -testPlan Mivu`,
  explicit `-only-testing:` selectors, `-parallel-testing-enabled NO`. Synthetic text only.

## Native results

| Selection | Result |
| --- | --- |
| `MivuTests/CoachReplyNotificationTests`, `TellCoachTests`, `MivuServicesTests`, `CoachFlowTests`, `CoachInboxTests`, `CompanionRootIntegrationTests` | 48 passed, 0 failed |
| `MivuUITests/CoachUITests`, `MivuUITests/QuickLogUITests` | 16 passed, 0 failed (758 s) |

Result bundle (local): `~/Library/Developer/XcodeBuildMCP/workspaces/mivu-siri-coach-9a32e3d8d261/result-bundles/test_sim_2026-10-23T15-17-09-938Z_pid40833_d649beda.xcresult`

Earlier during Task 3, `CoachUITests/testFixtureMealCorrectionHistoricalReviewAndConversationRelaunch`
failed 4 times while the simulator was being booted and shut down by hand: the first Send tap was
ignored. On a settled simulator it then passed 5 times, including alternating runs against the
pre-Task 3 base (2/2 each), and it passed in the final run above. It is recorded as an environment
flake, not a regression, and remains a watch item.

## Blocked: Shortcuts app run on the simulator

The "Tell Coach" action appears in the Shortcuts app beside Log Food and Coach. Running it shows
"Unable to run App Shortcut". The existing main-branch "Coach" shortcut fails the same way. The
system log shows `linkd` rejecting the locally built app (`Unable to get teamId … Rejecting invalid
client due to requiresValidBundle`), so the simulator build has no signing team for App Intents
execution. This check is **blocked**, not passing.

## Physical iPhone checklist (owner)

Each item is **not run**. A simulator cannot show locked-device Siri, so do not advertise
hands-free completion until these pass on a signed build.

1. Unlocked: "Hey Siri, tell Mivu" → "What should I tell the Coach?" → speak a meal → "Sent to the Coach." and the turn appears in Coach.
2. Locked: same phrase → "Saved. Open Mivu after you unlock to see the Coach's reply." → unlock and open Mivu → the message is in Coach history with the spoken time.
3. AirPods or CarPlay invocation with the phone in a pocket.
4. Airplane mode, then reconnect: the message is saved and processed after the network returns.
5. A notification with the Coach's reply (or "Your message is saved…" if iOS ended the time) opens the Coach tab when tapped.
6. Notifications declined: Siri still confirms and the reply waits in Coach history.
7. Measured seconds between Siri confirming and the reply notification.
