# Pip: character and motion bible

Status: original illustration and continuously living Lottie motion contract,
17 October 2026. Pip is the only launch companion. Preserve the approved painted
identity in `storyboard.png`; the editable rig and render details are documented
in [`lottie-source/README.md`](lottie-source/README.md). The approved PDF motion
guide remains the visual authority for acting and composition.

## Identity and composition

Keep the original shaded orange fox, cream muzzle, chest and tail tip, brown
eyes and paws, and teal scarf. Preserve its face, proportions, silhouette,
scarf knot and direction in every pose. Animate the painted source with authored
image layers and masks; do not redraw the character or replace it with a
simplified design.

Today places a prominent full-body Pip beside intake below the date. Coach
places the original seated Pip above its compact horizontal composer. Native
text, keyboard, controls and navigation remain SwiftUI-owned. Keep feet grounded
and the illustration subordinate to meal content and readable controls. At
larger accessibility text sizes, preserve native text and scrolling.

Coach uses one registered seated rig from the original painting in every
semantic state, including its static fallback. Neutral joins preserve the same
seated silhouette. It does not use Today poses or a separately animated
character design.

## Motion contract

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

## Lifecycle and accessibility

Only an eligible visible root may play. Stop playback when hidden, covered, in
the background, under Reduce Motion, in Low Power Mode, or at serious or critical
thermal state. Show the matching static pose when animation is stopped or
unavailable. VoiceOver ignores decorative art; native status text carries
meaning. Preserve native controls, keyboard behavior and scrolling, and never
communicate saved or error status through color or motion alone.

## Current source QA and validation status

At 148 pt Coach, source QA measured resting head 2.325 pt/chest 2.292 pt and
submitted head 2.412 pt/paw tip 2.289 pt. These are not measured iPhone FPS. Coach
shares one painted rig; JSON fell from 162 layers / 976,470 bytes to 110 /
709,146 bytes (SHA-256 `57adc8d26d0a02c40fe737f6fffec39355c05fdfe112e3628ae87094686978f0`).
Original PNG and fallback bytes are unchanged. Current motion-pass counts and revision boundaries are recorded in
`docs/verification/2026-10-17-pip-expressive-motion.md`. The following results are historical baseline
evidence only.

## Historical baseline validation

Simulator motion and reference checks passed. Final native source `c0623c3`
passed 523 tests with 0 failures and 1 expected interactive sign-in skip;
the isolated cold-load regression/lifecycle run passed 47 checks, and the final
light/dark capture journey passed after that fix. The complete UI suite passed
37 tests with 0 failures/skips at `6707440`, before the isolated cold-load change.
The private draft is [#17](https://github.com/yakov103/mivu/pull/17). Physical
frame pacing, energy, thermals and manual phone acceptance remain pending.
