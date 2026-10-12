# Native MVP acceptance matrix

Status date: 2026-10-12. Main CI verified source
`9f02a1568701f62a2afd482bf02fc5ed9d9f30bb`. The final local aggregate also
passed on HEAD `251aafce42b3d3b8f9258f45c6dd8c784f33f01f` plus uncommitted native
UI changes to `DiaryStyle.swift` and `DiaryUITests.swift`. The final merged source
SHA and release rehearsal remain pending. English-only scope
follows the [current owner override](../superpowers/specs/2026-10-12-sample-mvp-addendum.md).

| Area | Evidence | Status |
|---|---|---|
| Review and integration | [PR #3](https://github.com/yakov103/mivu/pull/3) merged after whole-branch review and scoped fixes. | **Verified** |
| PR and main CI | [PR run 38230868591](https://github.com/yakov103/mivu/actions/runs/38230868591) and [main run 38232085280](https://github.com/yakov103/mivu/actions/runs/38232085280): 199 passed, 0 failed, 1 skipped each. Main app ZIP integrity and strict code-signature checks passed; it is simulator-only. | **Verified** |
| Final local aggregate | 200 passed, 0 failed, 1 skipped; exit 0 in 109.4 seconds. Result bundle `test_sim_2026-10-12T10-16-03-467Z_pid12767_0a4b06c1.xcresult`; run source was the uncommitted working tree described above, not a clean commit. | **Verified for tested working tree; final source SHA pending** |
| Core native journey | Capture, review, half correction, item editing, weight, history, cancellation and profile isolation passed the native journey tests. | **Verified** |
| Archive logic | Main suite includes photo/pending/revision roundtrip, acknowledged deletion propagation, folder-history and stale-restore tests. | **Automated tests passed** |
| English presentation | English focused suite 10/10; light, dark, accessibility-3 and accessibility-5 renders inspected. The accessibility-5/photo UI run passed 2/2 (23.3s), with Log meal hittable. Root inspected the dark accessibility-5 screenshot: English LTR, wrapped labels, no permanent horizontal clipping, and scrollable below-fold content. | **Automation and render verified; full VoiceOver remains open** |
| Actual Files backup | User-selected folder write/status, export/import, and fresh-profile restore with photos are currently being exercised. Automated archive tests do not prove this system file-provider journey. | **PENDING** |
| Physical camera, haptics and hardware accessibility | No physical-device result has been recorded. | **NOT_RUN_BLOCKED** |
| Initial unsigned release rehearsal | [Run 38226669674](https://github.com/yakov103/mivu/actions/runs/38226669674) produced private draft `v1.0.0-rehearsal.1` with five digest-validated assets. The unsigned device archive is not phone-installable. | **Verified; final rehearsal pending** |
| Signed IPA/TestFlight | Required Apple signing credentials are unavailable; signed delivery has not run. | **NOT_RUN_BLOCKED** |

Live ChatGPT recognition and Siri are intentionally deferred. Passing CI does not
claim remote backup sync, physical-device acceptance or pilot completion. Update
this matrix with the final source SHA, Files result and second release rehearsal
after those changes merge. A docs-only follow-up will record evidence against
that same immutable release source.
