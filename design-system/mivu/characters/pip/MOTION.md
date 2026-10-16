# Pip: character and motion bible

Status: selected identity and motion contract, 17 October 2026. Original Pip is
the sole launch character. The editable rig and runtime export are now in
`source/` and the app bundle; see `AUTHORING.md`. Reference drawings remain
concepts. Simulator integration and physical-device acceptance are tracked
separately in the implementation evidence.

## 1. Identity and authority

Use [reference.png](reference.png) for identity and light/dark appearance,
[context.png](context.png) for placement intent and
[storyboard.png](storyboard.png) for expression/gesture direction. The numerical
limits below take precedence over exaggerated storyboard poses. The context
image is a concept, not a pixel-perfect replacement screen specification.

Pip is a curious, reassuring orange fox: large pointed ears, cream muzzle and
chest, dark brown eyes/nose/paws, a broad cream-tipped tail and short teal scarf.
Preserve the scarf knot, eye shape and silhouette across poses. Do not replace
the scarf with a leaf or change the selected character into a new variant.
Personality comes from attentive eyes, asymmetrical ears and small paw gestures.
Pip acknowledges user actions without evaluating foods, calories or bodies.

Author clean vector fills from the concept. Suggested production swatches are
orange #F68A43, orange shadow #C95F2C, cream #FFE0B4, dark features #38251F,
teal scarf #287B85 and teal shadow #205A65. These are proposed vector tokens,
not sampled claims. Verify them against the selected art and native surfaces.
In dark mode keep Pip orange; use cream #F6D6AF and dark features #30241F,
reduce broad highlights, and retain separation between scarf and slate surface.
No global tint, glow, animated material or blurred shadow. A simple optional
ground shape is part of the artwork, never a costly live shadow effect.

## 2. Composition and rig

Author one 512 x 512 artboard named `MivuCompanion`. All poses, including scarf,
ears and tail, stay inside x=40...472 and y=32...472. Ground is y=472; body root
anchor is (256,472). Use contain fit, no cropping, no changing layout bounds.
The nose and gaze face gently toward the content. Keep the same facing direction
across appearances; do not mirror asymmetrical details when switching themes.

Create independently controllable groups:

| Group | Parts and pivot | Expressive job / limit |
| --- | --- | --- |
| Root / hips | Body root, hips, chest | Lean at most 4 degrees; total height squash/stretch at most 3%; no slot travel |
| Head | Neck pivot, muzzle, cheek shapes | Nod at most 6 degrees, tilt at most 8 degrees; eyes stay readable |
| Ears L/R | Separate base pivots, inner-ear fills | Curious asymmetry up to 8 degrees; never flatten both ears in shame |
| Eyes / brows | Lids, pupils, separate brows | Gaze at most 2% of head width; neutral, attentive, thoughtful and warm expressions |
| Mouth | Closed smile, subtle open smile | No teeth, speech shapes, lip-sync, or exaggerated distress |
| Arms / paws | Shoulder, elbow, paw; flat shapes | One small wave or open palm; avoid tiny independent fingers at runtime size |
| Legs / feet | Hip, knee, foot contact | Grounded stance; review stretch never becomes a jump |
| Tail | Base, middle, tip controls | Follow through at most 10 degrees; no whipping, offscreen sweep or perpetual wag |
| Scarf | Fixed collar/knot, two short ends | Delayed follow through at most 6 degrees; settle within the same reaction duration |

Keep the face above other foreground parts; the scarf must not occlude the mouth.
Use few deformation controls and clean shape paths. Avoid raster fur, complex
feathering, unnecessary masks, physics simulation and full-artboard effects.
Tail/scarf follow through is authored, deterministic and bounded.

One simplified rig must read at 40, 64 and 80 points. At 40 points, eye and brow
contrast, ears and tail carry the expression; omit fur notches and pad detail
that become visual noise. Do not add a size-dependent public binding unless
actual on-device review proves one necessary. Production preparation includes
1x/2x/3x screenshots in both appearances and static fallback parity.

## 3. Body-language vocabulary and timing

Milliseconds are elapsed from reaction start. All durations include settling.
Intermediate poses are drawing direction, not additional application states.
Use authored cubic easing with continuous position/velocity at joins; restrained
ease-out on arrival, gentle ease-in-out on reversals. No undamped springs.

| State / value | Full-body score | Timeline | End / meaning |
| --- | --- | --- | --- |
| Resting / 0 | Feet grounded, open eyes, relaxed smile, upright soft ears, tail held beside body, scarf still | No loop. Eligible blink: 0-50 close lids, 50-70 hold, 70-150 reopen | Still open-eye rest; present without seeking attention |
| Attentive / 1 | Eyes toward composer, head tilts 3 degrees, chest leans 2 degrees, one ear turns forward, paws relaxed | 0-150 ease into pose; then fully still | Focused typing gets a quiet companion |
| Thinking / 2 | One paw near chin, head tilt up to 4 degrees, alternate slight gaze, tail mostly still | 0-350 settle into thought, 350-700 small eye/ear change, 700-1050 return gaze, 1050-1400 return to identical start pose | Seamless 1400 ms loop only during real processing; no progress percentage |
| Saved / 3 | Small head nod, open paw at chest height, warm smile; tail tip follows by 40 ms | 0-70 anticipation, 70-190 nod, 190-280 small palm acknowledgement, 280-450 settle | Input saved locally; never implies analysis or backup finished |
| Reviewed / 4 | Gentle compression, cheerful grounded stretch with both paws, smile, soft tail lift | 0-90 anticipation (3% max), 90-260 stretch, 260-380 smile, 380-650 settle | Explicit review committed successfully |
| Recovery / 5 | Head tilt 4 degrees, relaxed brows, one open palm, ears upright-soft, neutral mouth | 0-200 ease into pose; then still | Calm assistance while existing error/retry text explains the problem |
| Greeting / 6 | Small one-paw wave, head tilt 5 degrees, attentive ears, one tail follow through | 0-100 prepare, 100-260 paw lift, 260-440 one wave, 440-700 settle | One greeting per eligible foreground session; no repeated tab-switch greetings |

The six small expressions in the identity sheet are exploratory; the seven
states in this table are authoritative. The sleepy seated storyboard drawing
is a relaxation reference only: production resting keeps eyes open between
blinks and has no sleep cycle. Tail/ear amplitude stays within section 2 even
when a storyboard pose suggests a larger gesture.

Resting blink is triggered once per 12 seconds of continuously eligible rest.
Use a cancellable one-shot deadline, not a forever loop or display-link timer.
Cancel on focus, processing, hiding, coverage, background, reduced motion,
power/thermal policy or character switch. Restart its eligibility interval on
return; never catch up missed blinks. No breathing/bobbing loop while resting.

## 4. Transitions, interruption and priority

Use 100 ms interruptible blends for ordinary changes between visible poses.
The 150 ms attentive and 200 ms recovery arrivals include their blend. Entry
into a one-shot includes its anticipation; do not append another delay.
When returning from a reaction, blend to the current underlying state during
the final 100 ms where possible; the host's duration deadline remains the hard
end. Stop/reset obsolete one-shots before resuming a hidden view.

Priority: hidden/static policy first, current recovery second, typing third,
fresh success fourth, processing fifth, eligible greeting sixth, rest last.
Typing immediately cancels greeting or celebration and starts the quiet
attentive transition. A new error cancels success feedback. No action, focus
change, save, navigation or keyboard waits for the character to finish.

Keep only the newest unconsumed success within 10 seconds; deduplicate by
profile ID + operation ID + event kind. Do not replay old receipts after
launch, backgrounding, profile change or character switch. A current processing
state can resume after a saved gesture. Recovery does not spin indefinitely.

Appearance changes update colors without restarting an action. Accessibility
and power restrictions cancel motion immediately and select the current static
fallback. When restrictions lift, return to current semantic state with no
catch-up celebrations. The standard OS navigation/keyboard animations remain
owned by SwiftUI and system accessibility settings.

## 5. Shared character contract, version 1

All future characters implement the same semantic gestures and deadlines;
their anatomy and acting may differ. No Pip-specific branches in diary/Coach.

| Contract item | Exact value |
| --- | --- |
| Selected stable ID / name | `pip` / `Pip` |
| Schema | `1` |
| Bundle resource path | `Characters/pip/mivu-companion.riv` |
| Artboard / state machine | `MivuCompanion` / `Companion` |
| Bound view model | `CompanionModel`, default instance with defaults below |
| `pose` | Number, integral values 0...6; default 0 |
| `darkMode` | Boolean; default false |
| `react` | Trigger; rest triggers blink; saved/reviewed/greeting triggers fresh one-shot |
| Static fallback prefix / preview | `Pip` / `PipPreview` |

Host sets `pose` and `darkMode` on the retained bound instance, then fires
`react` for an eligible one-shot. For attentive/thinking/recovery, setting pose
is enough. Repeating a genuinely new same-kind success fires `react` again.
Changing pose cancels the previous action. The rest branch ignores stale
reaction triggers on reattachment; it blinks only for a new eligible deadline.
The fallback for an unsupported pose/schema is safe resting art plus a local
diagnostic; normal data operations remain available.

Keep one pose state-machine layer to arbitrate gestures; use nested authored
motion for face, ears and scarf so competing layers do not key the same property.
The appearance binding changes palette without altering pose or event identity.
One-shot branches finish at rest and stop advancing; the host restores any
non-rest underlying pose at its duration deadline. A missing completion event
cannot leave a permanent celebration. Test transitions in the actual runtime,
including same-kind repeats, interruption and no-active-animation settling.

Export seven static light/dark vector pose assets, plus `PipPreview`.
Naming: `PipResting`, `PipAttentive`, `PipThinking`, `PipSaved`, `PipReviewed`,
`PipRecovery`, `PipGreeting`. Use asset-catalog appearance variants, fixed bounds
and authored static key poses. A paused arbitrary frame is not the static asset.

## 6. Future character choices without launch complexity

`CharacterDescriptor` contains `id`, `displayName`, `schemaVersion`,
`riveResourcePath`, `fallbackAssetPrefix`, `previewAssetName`.
`CharacterCatalog.bundled.characters` initially contains exactly Pip. IDs never
change when display names change. Validate unique IDs and compatibility.

Root-owned `CompanionSelection` is a value stored in SwiftUI `@State`, backed
by device-local UserDefaults key `selectedCharacterID`. Nil, unknown or removed
IDs normalize to `pip`; update the stored preference as well. It is shared
across local profiles, absent from diary archives and needs no database change.
Settings shows a static Pip preview and name now. With two or more validated
bundled descriptors, show a labeled, accessible native selection list with a
checkmark and static previews. Selecting a row persists immediately; no modal
confirmation or fake locked characters. Keep targets at least 44 points.

Switching character cancels loading/deadline tasks, pauses and releases the old
artboard/file, clears reactions and shows the new resting fallback immediately.
Keep one shared worker alive. A monotonically increasing load generation guards
every async completion; cancellation alone is insufficient. A stale completion
must release its result without attaching it. Instantiate/play at most one
character. A failed selected pack uses its fallback with retry on next eligible
attachment, not an unbounded retry loop. Selecting the same ID is a no-op.
Resolve an invalid ID to Pip before creating a runtime. Returning from Settings
uses the selected rest/current semantic pose, never a queued old celebration.

Adding a future character means authoring its compatible rig, static poses and
preview, validating them, and adding one descriptor. Test selection, recreation,
unknown IDs, failure and rapid switches with a second test-only descriptor that
can reuse Pip bytes. Do not ship a placeholder second character.

## 7. Rive + Swift implementation policy

Pin the official `RiveRuntime` package to 6.28.1 and retain one supported
`RiveViewModel`/`RiveView` player with its exact typed bound model instance.
Real sequential native testing exposed skipped alternate gestures in the
concurrency renderer; the supported synchronous renderer passed repeated
reactions and natural stopping. This verified compatibility decision supersedes
the originally planned Worker API. Do not mix renderer lifecycles, fork the
runtime or fire duplicate triggers to mask failures. See
[verification](../../../../docs/verification/2026-10-17-pip-runtime.md).

Make runtime calls on MainActor, with file reading off the main actor and a
cancellation/generation check before parsing. Pause the actual player when
hidden. A real pause edge resets its named artboard/machine and bound default
instance to discard unrendered old triggers; repeated hidden updates do nothing.
Use 60 fps for gestures and 30 fps for thinking, then measure on hardware.
Avoid 3D GPU-canvas setup for this 2D asset.

Settled state machines can stop advancing; use a still resting branch instead
of an endless idle timeline. Pausing preserves state, so reattachment must reset
an obsolete one-shot rather than resume its middle. Drive known data bindings,
not inferred internal machine states. See [Rive state-machine playback](https://rive.app/docs/runtimes/apple/state-machines).

In SwiftUI, keep runtime identity stable, defer loading until the first useful
screen is interactive, and never load files in body. Publish semantic changes
only; do not publish each rendered frame into view models or lists. Cancel
tasks on lifecycle/selection changes, verify generation after every suspension,
and use app-owned sanitized error diagnostics. No remote fonts/assets, texture
downloads, loops on hidden tabs or animation-based business callbacks.

## 8. Accessibility, placement and measurable quality

Today: one fixed 64-point slot alongside the date/summary. Coach: one 40-point
slot in an at-least-48-point status strip above the composer; text can wrap.
Only the selected, visible root plays. Settings preview is static. Detail
screens use native success/status text. Largest text moves Today's companion
above the date; it never shrinks labels or covers actions. Scrolling the slot
offscreen, a covering sheet, inactive tab or background suspends all its work.

Reduce Motion, Low Power Mode and serious/critical thermal state select static
poses and cancel all decorative deadlines. VoiceOver ignores decorative art;
native status text provides meaning and existing announcements occur once.
Honor Reduce Transparency/Increase Contrast, preserve 44-point controls and
never use color/gesture alone for saved/error status. No sound or idle haptics.
See [Apple motion guidance](https://developer.apple.com/design/human-interface-guidelines/motion)
and [Reduce Motion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityReduceMotion).

Proposed budgets, not measured results: .riv target <512 KiB, hard <=1 MiB;
tap/typing feedback p95 <=100 ms; average hitch time <5 ms/s and baseline delta
<=1 ms/s; peak memory delta <=20 MiB; 50 tab-switch settled growth <=5 MiB;
zero frames/timers while hidden; resting CPU <=baseline+2 percentage points.
Use the full spec for launch budget, sample counts, fixtures and hardware
procedure. Record runtime binary cost separately from the rig resource.

## 9. Authoring and delivery checklist

- [ ] Approve clean vector turnaround and 40/64/80-point light/dark sheet against selected reference.
- [ ] Build editable layered Rive source, exact schema and seven animation branches; verify loops and interrupt blends.
- [ ] Export production .riv and all seven static appearance pairs plus preview; test the exact packaged bytes.
- [ ] Record source provenance, rights, editor/runtime version, SHA-256, measured bytes and export instructions in asset-manifest.json.
- [ ] Verify real data binding, repeated triggers, static fallback, parse/missing/schema failures and rapid load races.
- [ ] Verify typing, captures, reviews, failures, profile changes, background, appearance and accessibility on the actual app.
- [ ] Record Release-device traces and baseline/candidate metrics; no simulator-only smoothness claims.

No `.riv`, editable rig or measured performance result is delivered by this
planning package. Production asset authoring is an explicit implementation
dependency, not completed by the illustrations or this document.
