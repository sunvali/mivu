# Coach chat history — scrolling feasibility

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

Remaining production follow-through: Task12 removes this fixture and adopts
one measured renderer. Task11 must protect reservation-time eviction in future
consumers: this controller already holds the reader anchor before reservation,
while the early VM response instruction alone is too late. Task14 integration
and Task15 physical scrolling/memory/latency/accessibility remain separate.
