# Conversational food tracking verification

The existing Mivu app now has a durable native Coach flow backed by the same
profile-owned SQLite diary. This record covers source
`5eacf91b72a83e34629d61e41604248852cac061`; it does not replace the historical
[baseline audit](2026-10-12-coach-feature-audit.md).

## Implemented slice

- Text and photos save before inference. Pending input survives relaunch and
  bounded network retries without duplicate meals.
- Strict local tools retrieve stored context/meals, look up optional nutritional
  evidence, log multiple foods, correct individual quantities and close days.
- Food operations and receipts commit together. Replies confirm saved records;
  receipt-free intake answers come from actual stored totals.
- Retrospective dates and waking-day choices preserve capture time zones.
  Unconfirmed model timestamps stay date-only; manual capture retains its time.
- Review-first estimates stay outside intake until accepted. Nutrition uncertainty,
  source information and original photo attachments remain available for correction.
- Coach, Today, History and Settings retain the English-only native design.
  Stable lazy message rows keep incoming replies visible at the largest text size.

## Local evidence

Final full-scheme command, run with authorized simulator-service access:

```sh
rtk proxy xcodebuildmcp simulator test --json '{"projectPath":"ios/Mivu.xcodeproj","scheme":"Mivu","simulatorId":"AVAILABLE_SIMULATOR_UUID","derivedDataPath":"WRITABLE_DERIVED_DATA_PATH"}'
```

Replace the placeholders with an available iOS 26+ simulator and writable derived
data directory. The actual run used iPhone 18 Pro / iOS 27, Xcode 27.0
build 27A266a, macOS 27.0.1 arm64. It started
`2026-10-12T16:39:31.998Z` and finished `2026-10-12T16:43:22.286Z`.
Exit status **0**; actual result-summary and named-case JSON agree:
**302 passed, 0 failed, 1 skipped**. The skipped case was the optional
`BrowserCallbackProbeTests/nativeAuthenticationBrowserReachesLoopback`.
Result bundle: `test_sim_2026-10-12T16-39-30-590Z_pid85446_1b05930e.xcresult`.

Independent Ponytail Review found and verified fixes for invented read-only
nutrition totals, unconfirmed exact timestamps and eager per-turn meal scanning.
Focused core/flow/backup and largest-text coverage passed 64/0/0; the final
row-presence performance correction passed its unchanged native case 1/0/0.
The full aggregate above subsequently covered the final source. Its retained
pre-swipe arrival screenshot was inspected: the completed reply is readable
above the composer. Three invalid-frame warnings remain unattributed; no failed
assertion or visual defect was traced to them.

## Acceptance boundaries

Inference tests use synthetic responses through the production engine and real
native persistence. They establish record/receipt behavior, not live provider
recognition or portion accuracy. Live text/image inference, owner browser consent,
the actual Files-provider export/restore, physical camera/haptics/VoiceOver and
pilot acceptance remain unverified. Optional nutrition lookup requires a private
runtime key; missing lookup stays an uncertain estimate.

Hosted PR/main evidence and final immutable delivery will be recorded separately.
Dated goals, workouts, trends and reports are the next
[P1 milestone](../superpowers/plans/2026-10-12-coach-p1.md); personalized coaching
and advanced functionality remain later milestones. This slice is not the
complete nutrition and fitness coach.
