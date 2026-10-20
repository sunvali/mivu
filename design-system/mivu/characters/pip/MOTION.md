# Pip: character and motion bible

Status: native layered-rig motion contract, 19 October 2026. Pip is the only
launch companion. Identity is the original orange fox in `reference.png` (cream
muzzle, chest and tail tip, brown eyes and paws, teal scarf, big pointed ears);
the character sheet remains the visual authority for acting, with the motion caps
loosened below. Source is `rig/pip.svg`; see [`rig/README.md`](rig/README.md).

## Identity and composition

Pip is a layered vector drawn by us, traced from the paintings and checked by
overlay. Artboard 512x512, ground line y 472, content inside x 40-472 / y 32-472;
it must read at 40, 64, 88 and 200 pt in light and dark. Today shows the standing
set; Coach peeks over the composer (character sheet p. 2): the seated set cropped at the
`data-peek` bar line (y 383), paws resting on it and on the field's top edge; long idle on
Today the curled set. Native text, keyboard, controls and navigation remain SwiftUI-owned,
and feet stay on the ground line. Pip is decorative: `accessibilityHidden(true)`.

## Runtime

`PipRigAsset` decodes `pip-rig.json` (under 512 KiB; the loader rejects more than
1,048,576 bytes) and `PipRigView` builds a `CAShapeLayer` tree. A pose is data (joint
rotation/offset/scale plus eye, mouth and gaze). Joints move with
`CASpringAnimation` started from the presentation layer, so any gesture interrupts
any other without a jump. Body springs settle with little wobble; ears, tail and
scarf follow 60 ms later on softer, bouncier springs. A head view swap lands inside
a blink, so a turn never reads as a cut. Ears are rooted under the head and front
legs under the chest, so no joint opens a gap: lifted legs bend at the elbow and
uncover plain body, never hidden layer edges. The lower leg and paw trail the upper
leg, and lifting one paw shifts the weight back a touch. The neck is hidden by every
head view, so a turn never shows a seam.
A gesture is a list of timed poses (`PipGesture`); `PipGestureLibrary` holds them
all and `gesture(for:)` is the only moment-to-gesture mapping. Adding one:
[adding-a-gesture](../../../../.agents/skills/mivu-animation/references/adding-a-gesture.md).

## Motion limits (loosened by the owner, 19 October 2026)

Pip may nod, tilt, bounce and hop (up to about 14 pt), squash up to 10%, and
breathe gently at rest. Feet always land back on y 472 and he stays inside the
artboard. Warm and affectionate beats are welcome. Never celebrate or comment on
food amounts; no confetti, points or streak counters. Recovery is never cheerful.

## Moments

Durations come from `MivuMotion` and the gesture library.

| Moment | Duration | Gesture |
| --- | ---: | --- |
| Resting | continuous | Gentle breathing plus living eyes and idle beats (below) |
| Greeting | 0.9 s | Ears pop, small hop, wave; morning adds a stretch and yawn (0.9 s), evening a softer wave (0.9 s) |
| Welcome back (a day or more away) | 1.6 s | Ears droop with puppy eyes, then a joyful wave |
| Attentive (typing) | holds | Leans in, ears forward, then holds the pose (1.6 s loop); eyes sweep with draft length |
| Submitted | 0.8 s | Anticipation dip, nod, paw lift; first visible response within 100 ms |
| Thinking (processing) | 1.4 s loop | Paw to chin, eyes look side to side, tail swish |
| Saved | 0.45 s | Happy closed eyes, nod, open paw, little bounce |
| Reviewed | 0.65 s | Grounded stretch, both paws up, smile |
| First meal today | 1.0 s | Heart eyes, wiggle, one heart rises |
| Day complete | 1.4 s | Both-paws cheer, hop, blush, two hearts |
| Curious (photo added) | 1.0 s | Eyes wide, leans toward the photo |
| Recovery | 1.8 s | Ears droop, head tilt, open palm over heart, calm mouth; then holds still |
| Tap | 0.8 s | Rotating giggle, ear wiggle, wink, tail flick; rapid taps escalate once to a shake-off; light haptic |
| Pat (long press) | 1.3 s | Leans into the hand, closed eyes, blush, tail wag, a heart drifts up |

During recovery or processing a tap gives only an ear twitch. Surface changes use
the native tab transition; the 350 ms native focus and keyboard sizing animation is
separate from rendering. Saving and navigation never wait for animation.

## Priority and presentation rules

policy > recovery > typing > fresh success (including affection and habit
moments) > processing > tap/pat > greeting > idle beats > rest.
Accepted submit feedback begins before its first await using a separate signal with
profile, operation and transient attempt IDs; a fresh retry gets its own attempt
and re-observing one does not replay it. Saved is emitted only after durable local
capture and queues behind the submit gesture. Feedback is deduplicated by profile,
operation (and attempt), lives 10 s (`MivuMotion.feedbackLifetime`) and only the
newest fresh success plays. Profiles never share reactions. Errors, typing,
hidden/background and policy cancel stale feedback; expired reactions do not replay.

## Policy and accessibility

`MotionPolicy` allows animation only for an eligible visible root. Reduce Motion,
Low Power Mode, serious or critical thermal state, and hidden, covered or
background state show the same rig as a static pose with zero animations and zero
timers (the idle scheduler stops). VoiceOver ignores the art; native status text
carries meaning and never relies on color or motion alone.

## Living eyes and idle

Eyes blink on their own (a drawn blink: half-shut, shut, half-shut, open in 160 ms) and follow `look(at:)`;
with no gesture playing the head follows a beat later inside its view (face slide plus a nod up to 3 degrees, never a
view swap), as the sheet's "tiny gaze changes" ask (gaze leads, then the head turns for
a larger glance or a head view swap). `PipIdleScheduler` picks a beat every 2-6 s:
blink, double blink, glance, ear flick, weight shift; yawn and stretch after 30 s
of quiet; on Today a tail hug and then curl-up after 90 s. A curled Pip only
blinks and flicks an ear until the next input; any tap or app event wakes him.
Beats never repeat back to back and are skipped by anything higher in priority.

## History

The Lottie player and its painted-atlas pipeline (October 2026, `pip.json`, atlas,
matte and eyelid PNGs, `lottie-source/`) were removed in favour of the native rig.
That contract is preserved below and in
`docs/superpowers/specs/2026-10-17-pip-lottie-fidelity.md` and
`docs/verification/2026-10-17-*`; its caps and timings no longer apply.

<details>
<summary>Retired painted-atlas motion contract (historical)</summary>

### Motion contract

The 512×512 Lottie composition uses the illustrated source atlas through
independent image layers, masks and authored transforms. Head, ears, torso,
paws, tail and scarf move gently around grounded feet. Continuous motion keeps
Pip visibly alive without abrupt gestures: 4–5 second chest/head breathing,
grounded idle and typing paws, asymmetric ear motion, tail/scarf follow-through,
and an occasional embedded painted blink.
The blink is part of the resting loop; the presenter does not schedule a
separate idle blink timer.

| State | Duration | Acting and meaning |
| --- | ---: | --- |
| Resting | 8 s loop | Continuous quiet breathing, ear/scarf/tail motion and embedded painted blink |
| Attentive | 8 s loop | Quieter continuous motion while the user types |
| Thinking | 4 s loop | Slow, restrained movement while processing |
| Recovery | 4 s loop | Calm, explanatory movement; never a frozen frame or success signal |
| Submitted | 800 ms | Immediate ear perk, nod and paw lift; visible response targets the first 100 ms |
| Saved | 800 ms | Gentle acknowledgment after durable local capture, then resting |
| Reviewed | 1 s | Gentle review acknowledgment, then resting |
| Greeting | 1.2 s | Unhurried welcome, then resting |
| Coach | Same state timings | Seated original painting throughout; static fallback uses that same pose |

Do not animate the Lottie layer tree through UIKit view transitions: that can
blend unrelated atlas poses and flash other Pip scenes. Apply every timeline
update without UIKit view animation. Coach keeps the same seated rig through
neutral joins, with no artwork dissolve. Submitted uses an explicit 80 ms
snapshot bridge on both surfaces; other Today pose changes use 350 ms. Surface
changes use the native tab transition and do not fade artwork across surfaces.
The 350 ms native focus and keyboard sizing animation remains separate from
character rendering. Saving and navigation never wait for character animation.
Accepted submit feedback begins before its first await using a separate signal
with profile ID, operation ID, transient attempt ID and acceptance time. A fresh
accepted retry gets its own attempt; re-observing an attempt does not replay it.
Saved feedback is emitted after durable capture and queues behind the submit gesture; data work never waits.
Error, typing, hidden/background and Reduce
Motion cancel stale feedback. Saved means durable local capture only. Cold load
can outlast the 800 ms submitted marker; expired reactions do not replay. Recovery
is not a success state.

### Lifecycle and accessibility

Only an eligible visible root may play. Stop playback when hidden, covered, in
the background, under Reduce Motion, in Low Power Mode, or at serious or critical
thermal state. Show the matching static pose when animation is stopped or
unavailable. VoiceOver ignores decorative art; native status text carries
meaning. Preserve native controls, keyboard behavior and scrolling, and never
communicate saved or error status through color or motion alone.

### Current source QA and validation status

At 88 pt Coach, source QA measured submitted face 2.507 pt/paw tip 1.687 pt
and saved face 2.474 pt/chest 2.214 pt. Today breathing is unchanged. These are not measured iPhone FPS. Coach
shares one painted rig; JSON fell from 162 layers / 976,470 bytes to 110 /
710,323 bytes (SHA-256 `5a39809af6996b9a4c8eb6dc6a21776c90bf192de3071b35eeb75ac4dd54b06d`).
Original PNG and fallback bytes are unchanged. Current motion-pass counts and revision boundaries are recorded in
`docs/verification/2026-10-17-pip-idle-and-coach.md`. The following results are historical baseline
evidence only.

### Historical baseline validation

Simulator motion and reference checks passed. Final native source `c0623c3`
passed 523 tests with 0 failures and 1 expected interactive sign-in skip;
the isolated cold-load regression/lifecycle run passed 47 checks, and the final
light/dark capture journey passed after that fix. The complete UI suite passed
37 tests with 0 failures/skips at `6707440`, before the isolated cold-load change.
The private draft is [#17](https://github.com/yakov103/mivu/pull/17). Physical
frame pacing, energy, thermals and manual phone acceptance remain pending.

</details>
