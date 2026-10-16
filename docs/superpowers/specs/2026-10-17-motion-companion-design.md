# Mivu motion and everyday companion

Date: 2026-10-17, Asia/Jerusalem.

Status: written specification for owner review. The owner approved the hybrid
SwiftUI/Rive approach and the character/behavior direction in conversation.
This document has not yet been approved for implementation planning.

## 1. Intent and existing baseline

Make Mivu feel responsive, fluid, and playful while retaining the Precision
Glass interface, useful food-diary workflows, and high performance. The owner
chose an everyday animated companion on Today and Coach, with brief reactions
to saves and reviews. Preserve the approved light/dark semantic palette.

Success means interactions respond immediately, the companion acknowledges
real operations, and scrolling and typing remain smooth on a physical phone.
Animation must never delay a save, obscure an error, or interfere with editing.

Inspected implementation: `/private/tmp/mivu-local-hooks`, based on `897d1a2`
on the color branch. Its native source is `7ad18cb`; later changes are docs.
The color changes are in PR #16 and are not assumed merged. Implementation must
start from a revision containing those changes and record the exact baseline.

Relevant existing behavior:

- `DiaryViewModel.captureReceipt` and `CoachViewModel.captureReceipt` follow
  durable local capture and snapshot refresh. They do not prove analysis or
  backup completion.
- `MealDetailView` calls `acceptReview` through `DiaryViewModel.change`, which
  reports success or failure. This is the integration point for review feedback.
- `DiaryStyle` already guards numeric transitions with Reduce Motion; Today
  and Coach already provide capture haptics. Reuse these instead of stacking
  duplicate feedback.
- Coach uses `CoachHistoryWindow`, stable row identities, explicit pagination,
  and intentional scroll-follow behavior. Preserve those contracts.

## 2. Selected approach and scope

Use SwiftUI for navigation, controls, sheets, numeric changes, and layout
transitions. Use one bundled, original Rive character for expressive reactions.
The alternative native-only character would require bespoke rigging code;
prerendered clips would make interruption and blending less flexible.

This scope includes Today, Coach, successful review feedback, shared motion
tokens, the animation asset, lifecycle/accessibility policies, and verification.
Diary, Progress, Capture, and Settings retain their existing flows and receive
only shared native motion where relevant. They do not get additional mascots.

No new gamification, streak penalties, reward currency, notification campaigns,
voice/lip-sync, sound effects, background animation, or changes to food analysis.
No database migration, remote asset downloads, paid services, or new analytics.

## 3. Character and visual language

Create an original rounded teal creature, with two expressive eyes, a small
mouth, short arms, and a recognisable asymmetric silhouette: one soft peak on
the head. Keep the design readable at 40 points. Avoid a generic glowing orb,
medical claims, a Duolingo lookalike, or shiny glass effects on the character.
Its personality is warm, curious, and playful; it never looks disappointed in
the user or judges food, calorie intake, or body weight.

Use teal from the approved palette, a pale face detail, and dark expressive
features; provide an authored dark palette rather than applying a global tint.
The character is opaque vector artwork against existing content surfaces.
Preserve neutral native glass navigation. Do not change the app icon or wordmark.

Before rigging, produce one character sheet covering front/three-quarter view,
light/dark use, the seven poses below, and 40/64/80-point scale previews. Review
the artwork against this brief before treating it as the production asset.

### Placement

| Surface | Placement and size | Behavior |
| --- | --- | --- |
| Today | 64-point companion beside the existing date line, within the summary section | One greeting per foreground session, then resting; reactions reuse this slot |
| Coach | 40-point companion in a reserved 48-point status strip above the composer | Remains available while reading; does not insert animated conversation rows |
| Empty Coach | Same status-strip companion; preserve existing empty-state text | Greeting uses the same character instance, not a second illustration |
| Review detail | Existing success text/native feedback; no extra character | Returning to Today/Coach may show one fresh review reaction |

At accessibility Dynamic Type sizes, Today puts the companion above the date.
Coach keeps the 40-point illustration but allows its adjacent status text to
wrap and the strip to grow. Text is never scaled down to fit. The character
frame does not resize between poses. No reaction shifts the composer, caret,
scroll anchor, or primary action.

## 4. Motion and event contract

Durations below are product targets, not claims about measured performance.
All decorative transitions can be interrupted; none gates an operation.

| Pose | Trigger | Animation and duration | Exit |
| --- | --- | --- | --- |
| Greeting | First eligible visible companion in a foreground session | Small wave and head tilt, 700 ms | Resting |
| Resting | No active task or feedback | Still resting pose; one 150 ms blink every 12 seconds while eligible | Relevant event |
| Attentive | Coach field focused | One 150 ms gaze transition; then still while typing | Focus ends or operation state changes |
| Thinking | Visible Coach is actively processing input | Gentle 1.4-second looking/thinking loop, no fabricated progress | Real processing ends or policy pauses it |
| Saved | Durable input capture succeeds | Small nod and arm gesture, 450 ms | Current resting/attentive/thinking state |
| Reviewed | User accepts an estimate successfully | Small cheerful stretch, 650 ms | Current resting/attentive state |
| Recovery | Active operation reports an error or waiting for connection/network | One 200 ms concerned-but-calm tilt; then still | State resolves or is dismissed |

“Saved” means **input saved on this iPhone**. It must not imply nutrition has
been estimated, approved, backed up, or synced. “Reviewed” means the accepted
review committed successfully. Existing labels remain the source of truth.
Do not celebrate passive snapshot refreshes, automatic analysis completion,
historical records, weight changes, or calorie totals.

Native motion uses existing platform transitions for navigation, sheets, tab
selection, and keyboards. Keep numeric transitions at 250 ms and the existing
Coach follow transition at 200 ms. Newly inserted success/status content uses
180 ms opacity transitions without shifting the mascot frame. Use one shared
set of named durations; no global implicit animation on a whole screen or list.
Native controls provide press feedback; do not add a competing scale animation
to system glass buttons. Keep the existing capture success haptic, exactly once.
Review success may use one matching success haptic after commit; no idle haptics.

### Arbitration and event lifetime

There is at most one playing companion, on the selected, visible root screen.
Profile changes, backgrounding, a covering sheet, or navigation to a detail
screen stop playback. Returning restores current state, not an old animation.
Scrolling Today’s companion outside the viewport also pauses it.

Policy overrides come first, then a current operation error, explicit user
interaction, a fresh success reaction, active processing, greeting, and rest.
Typing cancels a celebration and enters the quiet attentive pose. Processing
may remain true underneath a brief saved reaction; afterward thinking resumes.
Network waiting uses the recovery still pose, not an endless thinking loop.

Deduplicate feedback by profile ID, operation ID, and event kind for the active
foreground session. On initial attachment, establish receipt baselines without
replaying historical receipt values. Clear transient feedback on profile change,
sign-out, and backgrounding. Keep only the newest pending success; never queue
a chain of celebrations. A success hidden by an editor/detail can be consumed
once on return within 10 seconds of commit, otherwise discard it. No persistent
event storage is needed. Errors and success receipts remain in their existing UI
even when decorative reactions are suppressed.

## 5. Small implementation boundaries

Keep persistence, inference, and analytics independent of animation:

1. A small root-owned `CompanionPresentation` holds transient event identity,
   expiry, selected surface, and the resolved pose. It consumes semantic events
   and lifecycle flags; it never reads photos or computes nutrition.
2. `CompanionView` owns the Rive view lifetime and accepts pose, appearance, and
   playback eligibility. Runtime updates must not publish animation-frame state
   back into `DiaryViewModel`, `CoachViewModel`, or a parent screen.
3. `MotionPolicy` derives allowed motion from Reduce Motion, Low Power Mode,
   thermal state, scene phase, focus, and actual surface visibility. Keep it a
   small value/policy function rather than a new service framework.

Suggested home: `ios/Mivu/Design/` for these focused files and motion tokens.
Root integration belongs in `Diary/TodayView.swift` (which owns the tab shell),
with adapters in `Coach/CoachView.swift`, capture receipts in existing models,
and explicit successful-review receipt emission in `Diary/MealDetailView.swift`
or a minimal view-model helper. Emit review feedback only if `change` returns
true and the expected profile is still selected. Do not observe every snapshot
and infer success from incidental changes.

Load the bundled asset after the first useful screen is interactive. Keep one
shared loaded file/worker and at most one playing artboard. Inactive tab views
must not retain independent ticking players. Reuse existing view identities.
No synchronous asset decoding, image preparation, or network work in `body`.

## 6. Rive delivery contract and failure handling

Deliver a real editable character source plus `mivu-companion.riv`, with:

- Artboard `MivuCompanion`, state machine `Companion`, and documented binding
  schema: integer `pose` (0 resting, 1 attentive, 2 thinking, 3 saved,
  4 reviewed, 5 recovery, 6 greeting), boolean `darkMode`, trigger `react`.
  Repeated fresh events of the same kind fire `react`; a new pose cancels the
  current one-shot. One-shots return to their resting drawing; the host restores
  the current semantic pose at the specified duration.
- Layered rig, reusable expressions, seven completed poses/transitions,
  identical layout bounds, no embedded text, audio, remote fonts, or external
  textures. Pausing must stop the player, not merely hide its view.
- Light/dark static vector fallback drawings with the same silhouette.
- An asset manifest with source ownership/provenance, file checksum, schema,
  runtime compatibility, and export instructions.

Target a character file below 512 KiB; hard limit 1 MiB. Record the measured
runtime/library contribution to the app separately instead of attributing it
to the character asset. Confirm asset and runtime licensing before bundling.
Do not accept new account terms, buy tooling, or substitute a stock character
without authorization.

Use the official Apple runtime through Swift Package Manager. Resolve and pin
one stable compatible version during planning/implementation, record the exact
version in `Package.resolved`, and test this asset against it. The current
repository has no Rive dependency. Follow the selected version’s threading and
playback APIs; new runtime API calls still require MainActor even when worker
processing is concurrent.

An illustration or motion storyboard is not a functioning Rive asset. Asset
authoring/export is a required deliverable. If the available workflow cannot
produce and validate the rig, report that specific dependency as incomplete;
do not claim the companion shipped using a static image or placeholder rig.

If loading, parsing, binding, or rendering fails, show the static fallback in
the same reserved slot and preserve normal app behavior. Log a sanitized local
diagnostic without meal text, photos, account identifiers, or tokens. An asset
failure must never block launch, editing, saving, or navigation.

## 7. Accessibility and lifecycle

- Reduce Motion: static poses only; no blink, squash, travel, loops, animated
  number interpolation, or custom scroll animation. State changes update text
  and pose immediately. Keep native system accessibility behavior.
- Low Power Mode or serious/critical thermal state: use static poses, avoiding
  idle/processing loops and decorative one-shots until the condition clears.
- Background, covered screen, inactive tab, offscreen character: stop playback
  immediately and cancel pending decorative timers. No background tasks for it.
- VoiceOver: the illustration is decorative and hidden from the accessibility
  tree. Existing actionable text and status labels remain accessible. Announce
  an operation once, not again when a character pose changes. No focus stealing.
- Dynamic Type: preserve readable wrapping and at least 44-point targets.
  Increase Contrast and Reduce Transparency must preserve existing palette and
  opaque content rules. Test both light and dark appearances.

## 8. Performance acceptance

The following are proposed project acceptance budgets, not measured results or
Apple/Rive guarantees. Record baseline and candidate on the same physical
iPhone, OS, Release configuration, synthetic data, and nominal thermal state.
Use 30 synthetic diary days, 90 meals with photos, and 100 Coach turns; retain
bounded Coach pagination. Use local deterministic inference fixtures for timing
so network variability does not mask rendering regressions. Exercise real
network behavior separately for correctness.

| Measure | Acceptance |
| --- | --- |
| Process-cold launch to usable screen | Median of 10 launches no more than 5% or 50 ms slower than baseline, whichever allowance is larger; asset loading never gates usability |
| Tap/typing to first visible feedback | p95 at or below 100 ms across 30 samples per interaction; no deliberate waiting for animation |
| Scroll/typing animation hitches | Three 30-second runs per journey; average hitch time below 5 ms/second and no more than 1 ms/second worse than baseline |
| Memory | Peak resident-memory increase at most 20 MiB over the same baseline journey; after 50 Today/Coach switches, settled memory within 5 MiB of the candidate’s first settled cycle |
| Idle and hidden work | No Rive frames or decorative timers while hidden/backgrounded; 60-second resting CPU average no more than 2 percentage points above baseline |
| Asset | `.riv` at most 1 MiB; record total installed binary/resource size delta separately |

Measure with Instruments/SwiftUI profiling and appropriate native performance
tests; record traces, source revisions, device/OS, configuration, sample counts,
and actual metrics. Native UI follows the device’s refresh behavior; character
reactions may target 60 fps and thinking 30 fps independently. Do not claim
120 fps based on a simulator, screenshots, or an API choice.

If the baseline already fails an absolute limit, report both values and the
specific bottleneck; do not silently weaken the budget. Profile repeated
thumbnail decoding and Progress calculations only if traces implicate them.
Avoid speculative cache/database changes or replacing Coach’s accessible eager
page rendering with an unverified lazy container.

## 9. Verification and completion

Add focused policy/event tests for successful capture, failed persistence,
explicit review success/failure, duplicate receipts, expired events, profile
switch during work, cancellation, typing interruption, and policy precedence.
Use controlled time rather than real sleeps for expiry assertions.

Exercise native UI flows for capture/save/review, retry/offline waiting,
rapid tab changes, scrolling older Coach messages while new content arrives,
typing during a reaction, switching profile, and background/foreground changes.
Verify resource-load failure using a deterministic fixture. Confirm full
interaction remains available with the fallback asset.

Inspect screenshots and short recordings in both appearances, default and
largest Dynamic Type, Reduce Motion, Reduce Transparency, and Increase Contrast.
Check VoiceOver reading order and that status announcements are not duplicated.
Verify haptics and scrolling on hardware. Existing persistence and provider
acceptance gaps must remain explicitly separate from motion acceptance.

Completion requires the authored asset and fallback, tested integration,
required native checks through XcodeBuildMCP, physical-device performance
evidence against the stated budgets, independent review, updated design tokens,
and a private PR. Install the verified build in place on the owner’s phone
when implementation is authorized; do not reset its records. Merging follows
the owner’s applicable authorization, not this design document alone.

## 10. Research basis

- [Duolingo character animation](https://blog.duolingo.com/world-character-visemes/):
  documented use of interactive Rive character states and synchronized reactions.
- [Duolingo’s asset handoff](https://rive.app/blog/creative-technologists-duolingo-s-solution-to-the-designer-to-developer-handoff):
  animator/creative-technologist collaboration produces reusable runtime assets.
- [Duolingo performance engineering](https://blog.duolingo.com/unique-engineering-problems/):
  trace-driven startup improvements and deferred nonessential work. Its reported
  Android results are historical, not a benchmark for Mivu or proof about iOS.
- [Duolingo app size](https://blog.duolingo.com/emerge-tool-app-size/): artwork
  complexity and unused assets require measurement even with vector resources.
- [Rive Apple documentation](https://rive.app/docs/runtimes/apple/apple), checked
  2026-10-17: SwiftUI integration, worker/thread requirements, pause and frame-rate
  controls. Confirm feature support against the exact pinned runtime.
- [Apple responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
  and [SwiftUI performance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance):
  profile actual app work and rendering updates; no library guarantees smoothness.

## Review handoff

Owner review of this written specification is the next stage. After approval,
write the implementation plan with ordered asset, policy, integration, and
verification tasks, then present execution choices. This document adds no app
code, dependency, runtime asset, or claimed performance result.
