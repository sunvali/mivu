# Coach chat history — Task 11A scrolling feasibility (historical)

This opening record is the dated Task 11A simulator feasibility evidence. It
describes the earlier synthetic spike, not the current production implementation
or Task 15 acceptance. The source and test evidence for the current checkout is
recorded separately below.

Selected renderer for Task12: the narrow self-sizing `UITableView` bridge with
hosted SwiftUI content. All four required cases passed cumulatively on the same
native inputs across iOS26.5 geometry and iOS27 actual VoiceOver runs. This proves
simulator feasibility in the recorded environment; it does not prove SwiftUI
incapable or establish physical-device acceptance. No production source is
activated by this spike.

## Scope and measurement

The DEBUG route requires `--diary-ui-test <UUID> --coach-scroll-spike` and branches
before `DiaryRootView`. It uses an injected synthetic actor, seven pages of 20
variable-height exchanges, delayed thumbnails and an off-viewport asynchronous
reply. It reads no real diary/profile/provider/photo data. The staged pure
`CoachPagedHistoryWindow` and early `CoachTimelineViewModel` use the eventual
page/viewport contracts, reservations and a 100-exchange resident+reserved bound.
The shipping legacy helper remains untouched; Task11 completes migration and
mutation handling.

The single temporary renderer is a self-sizing `UITableView` hosting SwiftUI
exchange content. It preserves a stable exchange ID and its viewport-relative
top using synchronous, nonanimated native layout correction. It has no height
cache. Reader preservation outlives instrumentation completion until intentional
user movement or semantic reflow.

Primary pixel evidence comes from actual stable-ID retained cell geometry at
public `UIUpdateLink.afterUpdateComplete`, consistently for baseline, after and
worst displacement. Idle stability requires at least three committed updates and
100ms. Missing committed anchors fail even if recovered; their after value is
null. Observation never changes controller policy. Pre-layout estimates and raw
accessibility notifications remain separate diagnostics. Continuous updates are
DEBUG-only and disabled on teardown.

The controlled partial-row baseline has negative top and at least 44 pt visible
remainder, established through real gestures and actual geometry. This does not
guarantee arbitrary epsilon-visible slivers. Task12 must choose and evaluate a
consistent meaningful visible controller anchor. Thumbnail coverage proves an
instantiated visible photo grows 80 pt, not offscreen photo remeasurement.

Dynamic Type judges semantic ID retention, readable text and same-ID action
activation after intentional reflow; fixed-category prepends separately retain
the pixel gate. It does not establish editor/detail navigation. The reply case
means off-viewport arrival, not OS background execution.

## Evidence and environment

All native jobs are root-owned serial XcodeBuildMCP runs. Evidence root:
`.superpowers/sdd/2026-10-18-coach-chat-history/`. Each run retains exact source
base/change SHA-256, UTC/command and flags in `provenance.json`, executed results
in `result.json`, native attachments in `Mivu.xcresult`, and extracted actual
values in `measured-traces.json` where available. Source base is
`4ebae52e97dd6325e0f6e3bd9842a59cac8f4aaf`.

Baseline: Debug Mivu, iPhone17 Pro iOS26.5 simulator
`42CE2315-9339-4EF1-A5B4-064444D0FA44`, SDK27, Swift6.0, parallel testing NO.
VoiceOver uses the real iOS27 automation service on iPhone18 Pro simulator
`80F2225B-C146-4E59-875C-35249B40F095`; iOS26 app support remains.
System appearance, Reduce Motion and display scale were not separately captured.
No defaults are inferred. Actual viewport geometry is recorded in telemetry.

Final native working-change SHA-256:
`89270593f9132d4b0bb46c9d253af84fcc31ea8abbec19405b686d2e80c05b9f`.
Both acceptance runs use that exact hash and source base above:

| Required XCTest method | Run | Actual result |
| --- | --- | --- |
| `testSpikePrependPreservesStationaryAnchorWithinTwoPoints` | `spike-final-geometry26-104142` | Passed; real partial anchor and lost-anchor negative control; photo314.6667→394.6667pt; growth-trial worst0.000002543pt, no committed loss. |
| `testSpikeBidirectionalEvictionAndBackgroundReplyPreserveReader` | `spike-final-geometry26-104142` | Passed; ten bidirectional/reply operations, worst0.0002492269pt, peak100, no committed loss. |
| `testSpikeDynamicTypePreservesSemanticPosition` | `spike-final-geometry26-104142` | Passed; large→accessibility2→large, same timeline, same-ID action reachable, separate fixed-category pixel gates. |
| `testSpikePagingPreservesAccessibilityFocus` | `spike-focus-committed27-104025` | Passed1/0/0,62.93s;89 actual committed queries retain exchange 41; worst4.55e-13pt, no committed anchor loss, pending=false at snapshot. |

Final26 passed 8/0/0 in 184.976 s: the three required UI methods plus five legacy
window methods. It produced 19 operation traces; all positive unchanged-font
trials stayed within 0.0002492269 pt and capacity 100. The sole lost anchor was the
explicit uncompensated negative control (anchor 122, after=null). The visible
photo grew exactly 80 pt and retained anchor 64. This is cumulative selected-case
acceptance across26+27, not a claimed single full-suite pass. Earlier trials are
not substituted for these final inputs.

Root launched this same26 build through the synthetic route and visually checked
readable varied heights with no overlap. Screenshot:
`spike-final-geometry26-104142/root-visual-variable-rows.jpg`. The app was stopped
after review. This checks the fixture layout, not production product design.

## Accessibility observation ruling

Actual iOS27 diagnostic runs observed SwiftUI accessibility nodes with no public
identifier/container. Paired unfocused-only/focused-only notifications included
real subframe nil query intervals, followed by actual same-exchange nodes. Speech
remained the old exchange and is not accepted as current-focus proof.

The approved gate is committed exchange-focus continuity: query
`UIAccessibility.focusedElement(using: .notificationVoiceOver)` at every committed
update while the trial is active. Prefer public ID/container; otherwise accept
only exact unique containment of the actual focused screen frame in an actual
resident visible cell. Reject nil, zero, ambiguous or off-window frames. No
prior-ID, expected-ID, label, speech or nearest-cell fallback is used. Every
positive unrelated/unmapped target fails immediately; any committed nil/unmapped/
different query remains in the event history and fails even if later recovered.
Raw notification intervals remain bounded diagnostics. No automatic refocus.

This is a scoped measurement decision/inference. UIKit headers define notification
payloads and the current-focus query, but do not guarantee pairing or transaction
continuity. Cost if wrong: a subframe or audible accessibility interruption could
be missed despite committed continuity. Physical VoiceOver acceptance remains
Task15; the report must not claim there was never a nil interval.

## Rejected evidence and remaining work

The naive SwiftUI RED measured the same exchange moving1→2955pt. A later SwiftUI
trial settled correctly but sampled a3346pt layout-rectangle excursion; it did
not capture retained-view/presentation geometry and cannot establish a displayed
jump or prove SwiftUI universally incapable. The bridge is a candidate selected
only from its final measured environment.

Earlier bridge passes with 52 pt overlapping rows are invalid variable-height
evidence. Corrected native sizing yielded genuinely varied heights. Intermediate
`rectForRow` excursions up to 85.67 pt were disproved by simultaneous actual-cell
and presentation geometry (`spike-diagnostic-100727/native-events.json`). Neither
layout estimates nor pre-layout cell absence are committed-frame acceptance.
A later real photo-growth loss began with a 0.000002543 pt visible sliver; the
controlled baseline was corrected without weakening the committed-loss gate.

At the time of this Task 11A run, production follow-through was still pending.
Task 12 later adopted the measured renderer. The physical scrolling,
memory/latency and accessibility gates remain separate from this historical
simulator evidence.

## Current implementation and evidence — 2026-10-18

The production Coach timeline uses a self-sizing `UITableView` bridge in
`ios/Mivu/Coach/CoachTimelineView.swift`; bounded page ownership remains in
`CoachTimelineViewModel.swift`, hosted by `CoachView.swift`. The current behavior
and limits are in [the behavior guide](../development/coach-chat-behavior.md).
The rows below follow recorded execution order. Run JSON, provenance and result
bundles are retained under
`build/verification/2026-10-18-coach-chat-history/sdd/`; the older
`.superpowers/sdd/2026-10-18-coach-chat-history/` path is a compatibility
symlink to that permanent evidence directory.

| Run and source evidence | Actual result | What it establishes |
| --- | --- | --- |
| `chat-camera-timeline-typed-164027`; commit `156032bd8e9573b458e2dfed3dbadf07c20c3314`; input SHA-256 `31bb892a47ca6dbaa1104a073a0a40e60a2b784106e6697dcfa90cec920a53cd` | **126 passed, 0 failed, 0 skipped**, 47.892 s | Committed camera/timeline baseline only. |
| `coach-ui-correction-unit-native-171718`; commit `7ce516b08e8db4982c05984d66ea082c22c35279`; native SHA-256 `b2dbb1af6a5a2bf21aba0adf29cfdd899b0bfd00f048829c53b14a6d11a5e0bf` | **778 passed, 7 failed, 1 skipped**, 246.393 s | Failed unit batch. Failures covered linked-workout ownership, exact diary navigation, four stale-consumer timeout cases, receipt facts, mounted photo publication (two parameter cases), and correction review. The structured report did not include all raw issues; a late timeline timer failure also arrived after its test ended. |
| `chat-runtime-repairs-173033`; commit `7ce516b08e8db4982c05984d66ea082c22c35279`; native SHA-256 `439068109bd216a66b84e2b4245e177c06d2fda3fc2a5899b1de4ef1154110f6` | **106 passed, 1 failed, 0 skipped**, 40.309 s | Failed focused rerun; the sole failure was malformed-JSON poison setup reporting `persistenceFailed`. |
| `chat-runtime-final-173516`; same commit; native SHA-256 `2819389a58fa131388762882e7a2f17442b6e1a88738e1be99852c7b10e32622` | **108 passed, 0 failed, 0 skipped**, 36.318 s | Focused runtime repairs and mounted current-generation workout-target regression; not a full-unit result. |
| `chat-final-ui-173618`; same commit and native SHA as above | **10 passed, 8 failed, 0 skipped**, 498.583 s; interrupted | The source inventory contains 59 UI test methods; request metadata selected 48, omitting 11 inherited methods. Seven failing declarations completed and a scrolling case was interrupted. Failures covered diagnostic viewport setup, Diary meal-link hittability, toolbar overflow and an obstructed Diary tab while the keyboard remained visible. This run establishes no geometry/focus acceptance. |
| `chat-final-wave-covering-175347`; commit `7ce516b08e8db4982c05984d66ea082c22c35279`; native SHA-256 `aa17ba57ac18cd8ee0163739fc156202d140d619c5219d79b19128d72af101c1` | **168 passed, 2 failed, 0 skipped**, 49.413 s | Failed consolidated wave. |
| `chat-final-wave-repaired-175542`; same commit; native SHA-256 `20a0dc0b46bcb7e6b947256575147e6113ab18a325a4dda0c763e0ccde3beef2` | **50 passed, 0 failed, 0 skipped**, 19.370 s | Focused repair evidence only; it is not final full acceptance. The iOS 26 geometry and separate iOS 27 VoiceOver spike evidence above remains historical Task 11A evidence. |
| `chat-runtime-ui-repaired-181938`; commit `7ce516b08e8db4982c05984d66ea082c22c35279`; native SHA-256 `20583252641f1bc1278c7813c868081f564155f882469f307d100a35db7cb172` | **1 passed, 7 failed, 0 skipped**, 525.919 s | Failed UI wave: yesterday correction passed; history, receipt navigation, Diary entry/source routes, calendar history, and Dynamic Type failed. |
| `chat-seek-measured-183116`; same commit; native SHA-256 `883d7b776898f48ff9f5e7c187683832c55ec5d27bc7d9c2072d1cba4cded87d` | **0 passed, 1 failed, 0 skipped**; XCTest case 79.379 s (result elapsed 5,988.528 s, including interruption) | Repeated seek/restoration UI case failed its waiter assertion. |
| `chat-viewport-feedback-201541`; same commit; native SHA-256 `ab378503461445d65180acc4946560e05b529639428bdb43eec867ea076270de` | **5 passed, 1 failed, 0 skipped**, 139.672 s | Four automatic-paging Swift Testing cases and the history seek UI case passed; calendar navigation UI case failed. The aggregate is not green. |
| `chat-affected-final-201905`; commit `7ce516b08e8db4982c05984d66ea082c22c35279`; native SHA-256 `0a90537ab777d2ebc6eb0be514321617a343d95e431a76dc7296469bcfe7b48e`; result bundle `build/verification/2026-10-18-coach-chat-history/sdd/chat-affected-final-201905/Mivu.xcresult` | **9 passed, 3 failed, 0 skipped**, 512.854 s | Four automatic-paging unit tests passed. Of eight UI cases, five passed: yesterday correction, equal-page seek/restoration, cold source route, legacy/repeated-calendar choices, and oldest-history draft preservation. Three failed because the receipt, Diary-day and Dynamic Type tests could not reach the `coachMealLink` action. Subsequent focused jump/receipt runs appear below. |
| `chat-native-jump-203318` (run `42626`); commit `7ce516b08e8db4982c05984d66ea082c22c35279`; native SHA-256 `b5df33e1c3190a620d66876fb7c47795e6beb477d6858d2c6d1e3affcfe94d22` | **6 passed, 1 failed, 0 skipped**, 177.264 s | Five Swift Testing methods and the Dynamic Type UI case passed; the receipt case failed because `coachNewMessage` was not hittable before the pan gate. |
| `chat-jump-accessibility-203710` (run `66706`); same commit; native SHA-256 `7abd55872ab0bc43aa94be06d80af06528d786a8c91a4464781b47a968f2483a` | **0 passed, 1 failed, 0 skipped**, 32.031 s | The receipt UI case could not find the jump control in the native accessibility list; no pan was attempted. |
| `chat-native-jump-accessible-204209` (run `80455`); same commit; native SHA-256 `109a90b8361c24969c4186b5aa71f015b69ecedb7bfd1df8aed7941e14cda0e7` | **4 passed, 2 failed, 0 skipped**, 38.008 s | Four unit methods passed; one control-owner assertion failed on a nil accessibility element, and the receipt UI target measured 43.99999999999994 pt high, just below its 44 pt gate. Neither failure reached a pan. |
| `chat-jump-touch-verified-204514` (run `48590`); same commit; native SHA-256 `1cfbce8975abbf7c71a70d0402a413985f7dafcd72c89a96d035552452605422` | **5 passed, 1 failed, 0 skipped**, 51.540 s | The receipt UI case passed an actual drag on the 170×48 pt Jump button, native table pan/offset comparisons, resident/page preservation, and the normal Jump-to-latest gate. Four unit methods passed; one failed two accessibility-prefix expectations. This focused run is not full UI acceptance. |
| `chat-jump-final-204713` (run `20786`); same commit; native working SHA-256 `945ca2aff5d5f283f0ec86795277856162fa75a221934e988ca2b62233abc305`; content proof SHA-256 `274b5bfffc737a0d043d675f0bb2cc939989466fe5712a8c3b2d8b5e40b622cf` across 199 files | **6 passed, 0 failed, 0 skipped**, 49.436 s | Five automatic-paging unit methods and the receipt UI case passed. The UI case exercised actual Jump-button pan and tap, reader state preservation, and bottom restoration within 2 pt. This is focused evidence, not the remaining full 58-selector UI run. |
| `chat-final-ui-remaining-204859`; source commit `7ce516b08e8db4982c05984d66ea082c22c35279`; native working SHA-256 `945ca2aff5d5f283f0ec86795277856162fa75a221934e988ca2b62233abc305`; content proof SHA-256 `274b5bfffc737a0d043d675f0bb2cc939989466fe5712a8c3b2d8b5e40b622cf` across 199 files; permanent artifacts in `build/verification/2026-10-18-coach-chat-history/sdd/chat-final-ui-remaining-204859/` | **Closed failed; XcodeBuildMCP wrapper summary 19 passed, 4 failed, 1 skipped, exit 1, 1,269.870 s. Raw XCTest reconciliation: 24 started, 23 completed (19 passed, 3 failed, 1 skipped), with one further started case interrupted.** | The 58-selector request ran with selected metadata for 48 methods; the source inventory contains 59 UI methods, with 11 inherited methods omitted from selected metadata. Raw completed failures were Diary tab-bar lookup after keyboard dismissal, earlier-message visibility, and fixture goals/workout assertions. A fixture meal-correction case was interrupted after an earlier assertion. Wrapper and raw failure counts do not reconcile, so this is failed partial evidence, not full UI acceptance. Six correction E2E cases passed; focused Jump run `20786` passed 6/0/0 on the same native bytes. |
| Normal push-hook native units, result bundle `.git/mivu-checks/native-cr75w04v/Mivu.xcresult`; commit `0c9ba10c4cdbb55366984baf82e57f021318a6b7`; native content SHA-256 `274b5bfffc737a0d043d675f0bb2cc939989466fe5712a8c3b2d8b5e40b622cf` | **796 passed, 0 failed, 1 skipped; succeeded, 231.112 s** | XcodeBuildMCP Debug on iOS Simulator `80F2225B-C146-4E59-875C-35249B40F095`. The skipped test was `nativeAuthenticationBrowserReachesLoopback`. The same push hook also reports 31 Python checks passed in 19.196 s. This is the full native unit result for the committed content SHA; it does not clear the broad UI failures or physical/provider gates. |
| Signed physical Release build/install/launch; `build/verification/2026-10-18-coach-chat-history/device-0c9ba10-signed/result.json`; commit `0c9ba10c4cdbb55366984baf82e57f021318a6b7`; native content SHA-256 `274b5bfffc737a0d043d675f0bb2cc939989466fe5712a8c3b2d8b5e40b622cf` | **Succeeded, 55.349 s** | XcodeBuildMCP Release on iPhone `E730F643-A1FB-50CC-819B-4060C5F10A74` (iOS 27.0.1); app `com.yakov103.mivu` installed and launched (process 24151), no fixture arguments, warnings or errors. Product path `/tmp/mivu-pip-device-derived/Build/Products/Release-iphoneos/Mivu.app`. This confirms installation and launch only; camera, VoiceOver, visual, performance and live-provider acceptance remain separate. The earlier no-team signing attempt is retained at `build/verification/2026-10-18-coach-chat-history/device-0c9ba10/`. |

Compile-only attempts executed zero tests and are not counted. A selected count is
not a completed count. Historical VoiceOver evidence used a separate iOS 27
automation run; the iOS 26 geometry run did not execute that service, and neither
run establishes physical-device acceptance.

## Current acceptance status

### Current delivery checklist

| Task group | Status |
| --- | --- |
| Tasks 1–13 | Implementation and source review complete. |
| Task 14 | Implementation complete; final lifecycle and VoiceOver acceptance pending. |
| Task 15 | Deterministic budget checks and six correction E2E workflows pass. Hardware and live-provider gates remain unverified. |
| Delivery completion | Native units passed and the Release app was installed/launched on the connected iPhone. Broad UI evidence remains failed, partial and unreconciled; visual review and remaining device/provider gates are pending. |

### Acceptance gates

| Gate | Status | Evidence needed |
| --- | --- | --- |
| Production implementation and source review | Complete in commit `0c9ba10c4cdbb55366984baf82e57f021318a6b7`; the frozen native content SHA remains `274b5bfffc737a0d043d675f0bb2cc939989466fe5712a8c3b2d8b5e40b622cf` (199 files) | Behavior and ownership are documented in the [behavior guide](../development/coach-chat-behavior.md). |
| Core correction E2E workflows | **6/6 passed** in the raw completed cases on native working SHA `945ca2aff5d5f283f0ec86795277856162fa75a221934e988ca2b62233abc305` | Grounded increment, ambiguous clarification, delayed capture context, stale manual-edit rejection, crash replay, and preserving a later manual value. The surrounding broad UI run failed and its wrapper/raw failure counts do not reconcile; these six named cases do not establish full UI acceptance. |
| Floating Jump and receipt scenario | **6 passed, 0 failed, 0 skipped** in focused run `chat-jump-final-204713` | Five automatic-paging unit methods plus one UI method; actual drag and tap, page preservation and bottom restoration within 2 pt. This is focused evidence only. |
| Final native unit suite and broad UI acceptance | Native unit suite passed **796/0/1**, 231.112 s, on commit `0c9ba10c4cdbb55366984baf82e57f021318a6b7` and content SHA `274b5bfffc737a0d043d675f0bb2cc939989466fe5712a8c3b2d8b5e40b622cf`; the skipped case was `nativeAuthenticationBrowserReachesLoopback`. The broad UI run remains failed partial evidence on the earlier working SHA: wrapper **19/4/1**, raw **19/3/1** among 23 completed, one additional started case interrupted, with unreconciled failure counts. The six correction E2E cases passed; full UI acceptance is not established. | Full units are available at `.git/mivu-checks/native-cr75w04v/Mivu.xcresult`. Review broad UI failure and reconciliation details above; retain separate physical-device, visual and provider gates.
| Physical camera, permission, interruption and photo import | Pending | Exercise on iPhone and record actual device/OS plus outcomes. |
| Physical iPhone installation and launch | **Complete:** Release app `com.yakov103.mivu` installed and launched on iPhone `E730F643-A1FB-50CC-819B-4060C5F10A74` (iOS 27.0.1), process 24151, from commit `0c9ba10c4cdbb55366984baf82e57f021318a6b7` / native content SHA `274b5bfffc737a0d043d675f0bb2cc939989466fe5712a8c3b2d8b5e40b622cf`; 55.349 s, no fixture arguments, warnings or errors. The first no-team attempt failed before install; the retry used the existing profile. | This confirms build/install/launch only. Physical camera, permissions/interruption, VoiceOver and scrolling remain unverified. Result: `build/verification/2026-10-18-coach-chat-history/device-0c9ba10-signed/result.json`; first attempt: `build/verification/2026-10-18-coach-chat-history/device-0c9ba10/`. |
| Visual acceptance | Pending | Review the finished native screens and interactions at intended text sizes and appearances. |
| Latency, memory and thermal behavior | Pending | Measure the approved device workload and report observations; do not infer a frame-rate target from simulator runs. |
| Low storage / ENOSPC and backup-folder acknowledgement | Pending | Exercise write failures and pending-state behavior separately from remote synchronization. |
| Authenticated live-provider semantics | Pending | Verify correction interpretation and persisted outcomes using an authorized authenticated session; synthetic fixtures do not establish provider behavior. |
| Pull request | [PR #19](https://github.com/yakov103/mivu/pull/19) is open as a draft for commit `0c9ba10c4cdbb55366984baf82e57f021318a6b7`. | Keep the UI failure, skipped unit, and unverified device/provider gates explicit; update the body when device results change. |

Implementation/source review and the six correction E2E workflows are complete.
The broad UI run closed with failed, unreconciled partial evidence. The full native unit suite passed 796/0/1 on commit
`0c9ba10c4cdbb55366984baf82e57f021318a6b7`. The signed Release app was installed and launched on the connected iPhone
without fixture arguments. This does not establish physical camera, VoiceOver,
scrolling, visual, resource or authenticated-provider acceptance. The broad UI
run remains failed partial evidence with unreconciled wrapper/raw failure counts;
overall acceptance is not established.
