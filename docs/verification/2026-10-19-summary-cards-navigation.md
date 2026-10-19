# Summary cards and predictable navigation

UI product source: `b03574329f1dcdb64e242ed74b6b5be794965463`.
Final native verification source: `dde12c53a7c10e55a873c0a0b7d9d4d20e06df88`,
which changes only a test's startup order after the UI product commit.
The final candidate and committed tree contain
the same 203 native files.
SHA-256 is `e0f481c22619d7d5665e3c2dfb5860146292ad5b20fbf290f6893b147d78edc1`,
computed over sorted repository-relative paths followed by NUL, file bytes and
NUL. Local evidence is under
`build/verification/2026-10-19-airbnb-navigation/`; ignored native artifacts and
screenshots are retained locally rather than hosted in the repository.

## Delivered behavior

The owner approved spacious cards for summaries and a clean Coach conversation.
Today, Diary and Progress share opaque semantic surfaces, 24-point corners,
20-point padding and subtle downward shadows. Related facts stay together;
there are no nested cards. Existing list rendering, query limits, status labels,
unknown values and coverage semantics remain. Today's three nutrient captions
use the full intake-card width. The shadow belongs to the background shape,
so it does not blur Pip or text. Light/dark and Increase Contrast use semantic
colors. The artwork, animation pack and runtime are unchanged.

Coach's native floating control is now a 48-point circular down arrow with the
spoken label “Jump to latest.” It remains owned by the table, including its
native pan relationship, accessibility routing and existing jump callback.
Nutrition disclosure labels can grow vertically rather than truncate. The
previous compact receipt and scroll-driven history loading remain in place.

Progress's coverage action selects the existing Diary tab rather than pushing a
second Diary root inside Progress. Four independent stacks and their existing
state owners remain. The reported tap on the older physical build was not
reproduced; removing the source-proven duplicate route does not establish the
cause of every possible physical-device navigation symptom.

The [navigation and layout guide](../development/navigation-and-summary-layout.md)
records the applied Apple navigation and Airbnb component research. The owner's
supplied screenshot is the visual reference; its personal data is not bundled.

## Simulator and visual verification

Serial XcodeBuildMCP runs used iPhone 18 Pro / iOS 27, Xcode 27.0 (27A266a),
Swift 6, locked packages and parallel testing disabled.

| Run | Result and boundary |
| --- | --- |
| Initial compile attempt | Invalid SwiftUI environment key prevented compilation; zero tests ran. Corrected to `colorSchemeContrast`. |
| `summary-navigation-verified-071649` | 12 unit cases and six UI cases passed; one navigation helper failed. Four-tab/settings returns, coverage-to-Diary, actual arrow drag/tap/reader restoration and card/large-text journeys passed. |
| `summary-final-072813` | Three UI cases passed after the bounded visual correction: summary cards at normal/largest text in both appearances, and Coach at largest text in both appearances. The draft navigation helper still failed. |
| `keyboard-diagnosis-073645` | Five units passed; the navigation helper failed. Preserved screenshot/hierarchy established that the gesture used pre-layout geometry and started over the keyboard. Table bouncing was already enabled. |
| `navigation-settled-074110` | One UI case passed, zero failed; 51.378 seconds. Waiting for settled on-screen keyboard/table frames corrected only the test. Actual dismissal drag, exact unsent draft, Diary/Progress/Weight/settings return and selected-root assertions all remain. |
| First required push run | 800 units passed, one failed, one skipped; 216.820 seconds. The existing off-page companion integration test timed out at startup; the push was blocked. |
| `companion-root-diagnosis-074649` | The unchanged companion root suite passed seven cases in isolation; 20.209 seconds. This did not erase the preceding full-run failure. |
| `companion-root-settled-074902` | Seven cases passed, zero failed; 22.673 seconds, after removing only the test's eager worker start. The real root now owns startup, preserving the original operation, history, pose and late-cancellation assertions. |
| Required push checks after the test repair | 801 native units passed, zero failed, one skipped; 202.972 seconds. All 31 script tests passed. The ordinary push succeeded without bypassing hooks. |

These passes cover seven distinct UI methods cumulatively, not the complete UI
suite or a single all-green batch. The final changes after the visual pass are
only test geometry synchronization and removal of temporary diagnostics; the
production layout is unchanged. The later one-line integration-test repair
also leaves production unchanged. Source tracing found that the test eagerly
started its suspended inference worker while the real root's initialization
could still cancel it for a profile reload. The root already starts the worker
after that reload; the test now follows this lifecycle. An additional
sandbox-blocked invocation ran
zero tests because the native log directory was inaccessible; the successful
rerun used normal native-tool directory access.

The final visual pass preserved 26 screenshots via XCTAttachments, exported to
`final-xcresult-attachments/` and copied with readable names to `final-visuals/`.
Normal light/dark images show separated summary cards and full-width nutrient
labels without the initial shadow haze. Largest accessibility text grows and
requires scrolling; these captures do not claim every line fits simultaneously
or that long ledger labels never wrap. The arrow remains compact at that size.
Its actual native pan and tap, 48-point geometry, spoken label, focus routing,
and reader restoration within two points have separate assertions.

Bounded source review and visual/test addenda are retained in `review.md` under
the evidence root. Source review reported no remaining findings; it is separate
from the executed native evidence above.

## Device boundary

The owner is away from the Mac and still has the previous installed version.
No physical-device installation or acceptance was attempted for this revision.
The earlier Release artifact documented in
[the prior layout record](2026-10-19-coach-chat-layout.md) belongs to `043a0c7`,
not this product source; build the current revision before a future installation.
Physical camera/VoiceOver, named rotor actions, frame-time/energy profiling,
authenticated provider behavior and the complete UI suite remain separate
acceptance work. PR [#19](https://github.com/yakov103/mivu/pull/19) stays draft;
no merge or release was performed.

The full unit evidence is retained as `required-push-native.json` in the local
evidence root. The skipped case is `nativeAuthenticationBrowserReachesLoopback`,
which requires a manual authentication-browser environment. This record is a
documentation-only follow-up; its native inputs match the tested source above.
