# Coach foundation verification — 2026-10-12

This page records the merged Coach foundation only. It supplements the [historical feature audit](2026-10-12-coach-feature-audit.md) and [P0 implementation plan](../superpowers/plans/2026-10-12-coach-p0.md); it does not revise their open acceptance scope. The completed foundation includes transactional native storage, structured inference transport, and a USDA adapter. The core Coach UI and complete coaching flow remain work in progress.

## Merged delivery

[PR #5](https://github.com/yakov103/mivu/pull/5) merged at **2026-10-12 12:16:50 UTC** as source commit [`acf0f1db289cc0ff362755ba85e6dce43a66ca2d`](https://github.com/yakov103/mivu/commit/acf0f1db289cc0ff362755ba85e6dce43a66ca2d). Its shipped foundation covers transactional storage, structured inference, and the USDA adapter. This is not evidence that the complete Coach experience is finished.

## Hosted CI evidence

| Run | Source and time | Result |
|---|---|---|
| [PR CI run 38246978998](https://github.com/yakov103/mivu/actions/runs/38246978998) | Actual test source `a37d2a12cecc528e3a4fcf6d8a0030efb30ca8e4`; artifact provenance timestamp `2026-10-12T12:12:23.121588+00:00`; macOS 26.6.2, arm64. | Exit 0; 232 passed, 0 failed, 1 optional skip. This run tested the PR source immediately before merge. |
| [Main CI run 38248045510](https://github.com/yakov103/mivu/actions/runs/38248045510) | Actual head `acf0f1d`; test-count line observed in the hosted log at `2026-10-12T12:21:53.920069Z`; Xcode 26.6, Swift 6.3.3, macOS 26.6.2, arm64. | Job completed successfully; 232 passed, 0 failed, 1 optional skip. The displayed time is the log observation time, not artifact provenance: the main run artifact was not downloaded. |

The one optional skip is reported as a skip, not a pass. The PR artifact provenance and the main-run log observation are distinct evidence sources and timestamps.

## Focused verification and review

| Scope | Result |
|---|---|
| Transactional storage and diary/day/archive/flow regression | 83 passed, 0 failed, 0 skipped. |
| Structured inference transport and probe compatibility | 47 passed, 0 failed, 0 skipped. |
| USDA evidence adapter | 11 passed, 0 failed, 0 skipped. |
| Independent scoped reviews | Marked Ship for the storage, transport, and adapter foundation. No live provider inference was performed. |

The initial PR CI attempt, [run 38244372379](https://github.com/yakov103/mivu/actions/runs/38244372379), failed 231 passed, 1 failed, 1 optional skip. The failure was limited to a callback-cleanup test parameter using a 100 ms startup budget. Commit `43d9d2b` changed the test cleanup deadline to 5 seconds; production callback behavior and the dedicated 100 ms test were unchanged. The isolated cleanup rerun passed 5/0/0, followed by the independent PR CI run recorded above.

## Scope and remaining gates

This is foundation evidence, not completion of conversational coaching. The persisted Coach domain behavior and connected native Coach UI are still being developed and have no completion claim here. Do not infer that uncommitted local Domain/UI work passed CI from these merged-source results. The audit's P1, P2, and P3 requirements remain pending.

No live provider request or live consent flow was used for these tests. No paid resource was created or enabled. The repository is private; distribution credentials and public distribution are outside this evidence. Files-provider roundtrip and physical-device Coach proof remain unverified. The unsigned rehearsal baseline remains source `7a86` with its previously verified assets; this foundation merge does not constitute a new rehearsal or distribution proof.
