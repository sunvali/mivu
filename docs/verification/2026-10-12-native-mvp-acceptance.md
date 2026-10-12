# Native MVP acceptance matrix

Status date: 2026-10-12. The hosted baseline and unsigned rehearsal are bound to
source `7a86d046200fa4e86e5110b96aa31fd479a99822`. English-only scope follows
the [current owner override](../superpowers/specs/2026-10-12-sample-mvp-addendum.md).

| Area | Evidence | Status |
|---|---|---|
| Review and integration | [PR #4](https://github.com/yakov103/mivu/pull/4) is merged; it merged externally while CI was running. | **Merged** |
| Hosted main CI | [Run 38236090700](https://github.com/yakov103/mivu/actions/runs/38236090700), source `7a86d046200fa4e86e5110b96aa31fd479a99822`; macOS 26.6.2 arm64; provenance `2026-10-12T10:29:43.930615Z`; exit 0; 200 passed, 0 failed, 1 skipped. | **Verified for this source** |
| Supplemental local aggregate | 200 passed, 0 failed, 1 skipped on working-tree HEAD `251aafce42b3d3b8f9258f45c6dd8c784f33f01f` plus uncommitted native UI changes to `DiaryStyle.swift` and `DiaryUITests.swift`. This is separate from the clean hosted/release source. | **Verified for that working tree only** |
| Core native journey | Capture, review, half correction, item editing, weight, history, cancellation and profile isolation passed the native journey tests. | **Automated tests passed** |
| English and accessibility presentation | English-focused suite 10/10; accessibility-5/photo-focused run 2/2. The dark accessibility-5 render was inspected: English LTR, wrapped labels, no permanent horizontal clipping, and below-fold content scrollable in the native list. Full physical VoiceOver remains unverified. | **Automation and render inspected** |
| Archive logic | Automated coverage includes photo/pending/revision roundtrip, deletion propagation, folder-history and stale-restore protections. This does not prove a real Files-provider journey. | **Automated tests passed** |
| Actual Files-provider backup/restore | No accepted end-to-end result for user-selected folder write, export and fresh-profile restore. Archive tests are not provider acceptance. | **UNVERIFIED** |
| Physical camera, haptics and hardware accessibility | No physical-device acceptance result is recorded. | **UNVERIFIED** |
| Unsigned release rehearsal | [Run 38238559422](https://github.com/yakov103/mivu/actions/runs/38238559422) succeeded on the hosted baseline. The private draft is [`v1.0.0-rehearsal.2`](https://github.com/yakov103/mivu/releases/tag/untagged-746cb4d76e3ed82ebe51). All five downloaded assets matched release metadata size and SHA-256; both ZIP integrity checks passed. The unsigned device archive is not phone-installable. | **Verified for source `7a86…`** |
| Signed IPA/TestFlight | Signed delivery was not requested by this tag-triggered rehearsal, so its signed job was skipped. Required signing secrets remain unavailable, separately blocking signed delivery. No signed or phone-installable artifact was produced. | **NOT_RUN_BLOCKED** |
| Conversational coach expansion | The native diary baseline still uses its sample analyzer. New coach requirements, design and plan are underway; this baseline provides no implementation, live inference, account eligibility or end-to-end coach acceptance evidence. | **IN PROGRESS; NOT VERIFIED** |

Passing simulator CI does not establish physical-device acceptance, remote backup
sync, Files-provider success, pilot acceptance, live ChatGPT diary inference or
TestFlight delivery.
