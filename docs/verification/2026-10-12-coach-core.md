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

## Hosted integration evidence

[PR #6](https://github.com/yakov103/mivu/pull/6) merged at
`2026-10-12T17:05:57Z` as `099e72694e4f27cc97b5c36453428df1f8009201`.
Its tree matches the reviewed PR head `3a57a34a927d6b361de204e783b7e7c0b6fe1654`.

The [PR run](https://github.com/yakov103/mivu/actions/runs/38279845129)
succeeded on actual tested merge source
`aef32fcdf513ebd0ab876f833d5d66e7d5839f2d`. Downloaded provenance records
`2026-10-12T16:55:29.771308+00:00`, macOS 26.6.2 arm64 and exit 0;
the named-case verifier confirmed **302 passed, 0 failed, 1 skipped**.
The runner used Xcode 26.6 / Swift 6.3.3.

The [main run](https://github.com/yakov103/mivu/actions/runs/38281956485)
also succeeded, on exact merged source
`099e72694e4f27cc97b5c36453428df1f8009201`.
Its downloaded log reports **302 passed, 0 failed, 1 skipped** at
`2026-10-12T17:12:27.741803Z`. This is a log timestamp; main artifact
provenance was not downloaded. The hosted checks prove simulator validation,
not live inference or physical-device delivery.

Final immutable delivery remains separate.
Dated goals, workouts, trends and reports are the next
[P1 milestone](../superpowers/plans/2026-10-12-coach-p1.md); personalized coaching
and advanced functionality remain later milestones. This slice is not the
complete nutrition and fitness coach.

The owner requested that core tracking be completed first, with a checkpoint
before personalized coaching and advanced features. That priority applies to the
remaining implementation; later milestones must not start automatically.
