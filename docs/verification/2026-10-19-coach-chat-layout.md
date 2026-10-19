# Coach chat layout refinement

Product source: `043a0c7c990262bd8efbd5010a35ea8986ea3b41`.
All 201 native files have content digest
`be60d85e1bc023066e5ea1b63d4c160a0d302bc46f199e701b1f9dda588bdb53`.
The final working-tree run and committed tree have identical native content.

## Changed behavior

One compact immutable food receipt replaces the repeated committed/current
summaries. It keeps committed quantities, date, energy, uncertainty and estimate
labels; macros expand through a full-row 44-point native disclosure control.
Review / Edit opens the current record. Later edits, moves and availability
warnings remain visible without repeating the record's full contents.

Coach keeps Pip at an 88-point artboard trimmed to 76 × 66 points on the canvas,
with stable dimensions while typing. Assistant text uses body type and spacing
separates exchanges. The composer uses native camera/send controls without the
extra enclosing panel. Today and the artwork/runtime are unchanged.

Scrolling requests older/newer pages through the existing bounded native path.
Available/exhausted edges allocate no bar or placeholder height. Loading/retry
feedback overlays the table, preserving its viewport. The focusable Chat history
button exposes named paging actions through that same measured-anchor path.

## Native verification

Serial XcodeBuildMCP runs used Swift 6, SDK 27, locked package versions and
parallel testing disabled. Local evidence is retained under
`build/verification/2026-10-19-coach-distill/`; these ignored artifacts are not
hosted by the repository.

| Run | Environment | Result and boundary |
| --- | --- | --- |
| `coach-distill-batch-061500` | iPhone 17 Pro, iOS 26.5 | 28 unit cases and 6 UI cases passed; 4 UI cases failed. The failures exposed undersized disclosure interaction, offscreen-turn lookup and invalid first-use/geometry assertions. |
| `coach-correction-batch-062808` | iPhone 18 Pro, iOS 27 | 1 native bridge unit case and 4 UI cases passed. Historical review had one premature offscreen-button existence assertion; scrolling then reached and accepted the review, and the remaining persistence checks completed. |
| `coach-final-layout-063617` | iPhone 18 Pro, iOS 27 | 2 UI cases passed, 0 failed: historical correction/review/relaunch and largest-text light/dark layout with the wrapped committed date. 213.926 seconds. |
| Required push checks | iPhone 18 Pro, iOS 27; Xcode 27.0 (27A266a) | 801 native units passed, 0 failed, 1 skipped; 206.894 seconds. All 31 script tests passed. |

Successful UI coverage is cumulative across the bounded repair passes, not a
fresh full-suite pass on one revision. It covers 11 distinct methods: real
scroll pagination/exhaustion; receipt dates/unknown nutrition; two grounded
correction/recovery cases; Diary navigation and exact source return; retained
history on new input; goals/weight/workout/budget/relaunch; historical meal
correction/review/relaunch; normal light/dark receipt/composer/disclosure;
largest-text light/dark; actual VoiceOver traversal to Chat history.
The final changes after the second pass are limited to accessibility-size date
layout and the historical test's reveal-before-assert ordering. Native unit
coverage is verified separately by the required push check. Its one skipped
case is `nativeAuthenticationBrowserReachesLoopback`, which requires a manual
authentication-browser environment. The exact successful hook record is retained
in `required-push-native.json` under the local evidence root.

The original immutable receipt checks, unrelated-food preservation, exact
submitted-turn reply ownership, 100-exchange capacity, exhausted-edge read
suppression, and stationary-anchor tolerance of 2 points remain asserted.
The four historical conversations retain distinct inputs and their own replies
after relaunch. No provider request is made by these fixtures.

Normal light/dark screenshots were inspected in `second-pass-visuals/`; final
largest-text captures are in `final-visuals/`. The duplicate current-food panel
and persistent paging bars are absent. Review / Edit and the committed date now
wrap naturally at accessibility sizes. Captured largest-text scroll positions
still show the existing floating Jump control overlaying part of the receipt;
the screenshots do not establish every line readable simultaneously. Native
scrolling remains required for long receipts.

Bounded source review and its accessibility/control addenda are retained in
`review.md` under the local evidence root. No remaining blocking source finding
was reported. Final date wrapping was checked by the root against actual pixels.

## Device and remaining acceptance

The Release build and development signing succeeded for the product source above
without fixture launch arguments. Installation did not complete: CoreDevice
returned error 4016, and a fresh device listing reported Yaakov’s iPhone (iOS
27.0.1, `E730F643-A1FB-50CC-819B-4060C5F10A74`) disconnected/unavailable.
The new build is not installed or launched. Reconnect and unlock the phone, then
install the existing signed artifact rather than rebuilding:
`/private/tmp/mivu-pip-device-derived/Build/Products/Release-iphoneos/Mivu.app`.
Build/result provenance is retained in `device-release-provenance.json` and
`device-release-result.json` under the local evidence root.

The actual iOS 27 VoiceOver service reached the history toolbar and preserved
its draft, stationary reader, page state and capacity. The bridge unit invokes
the shared paging callback directly. The public automation service cannot invoke
named rotor actions, so actual earlier/later/retry rotor invocation remains a
manual check. The complete UI suite, physical camera/VoiceOver, frame-time and
energy profiling, and authenticated live-provider semantics remain unverified.
No merge or release was performed. PR [#19](https://github.com/yakov103/mivu/pull/19)
remains a draft.
