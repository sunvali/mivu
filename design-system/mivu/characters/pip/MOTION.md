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
Pip visibly alive without abrupt gestures: slow breathing, small ear and scarf
settles, a restrained tail movement and an occasional embedded painted blink.
The blink is part of the resting loop; the presenter does not schedule a
separate idle blink timer.

| State | Duration | Acting and meaning |
| --- | ---: | --- |
| Resting | 8 s loop | Continuous quiet breathing, ear/scarf/tail motion and embedded painted blink |
| Attentive | 6 s loop | Quieter continuous motion while the user types |
| Thinking | 4 s loop | Slow, restrained movement while processing |
| Recovery | 4 s loop | Calm, explanatory movement; never a frozen frame or success signal |
| Saved | 1.5 s | Gentle acknowledgment after durable local capture, then resting |
| Reviewed | 1.8 s | Gentle review acknowledgment, then resting |
| Greeting | 2.2 s | Unhurried welcome, then resting |
| Coach | Same state timings | Seated original painting throughout; static fallback uses that same pose |

Do not animate the Lottie layer tree through UIKit view transitions: that can
blend unrelated atlas poses and flash other Pip scenes. Apply every timeline
update without UIKit view animation. Coach keeps the same seated rig through
neutral joins, with no artwork dissolve. Today may fade an explicit snapshot
overlay over 350 ms. Surface changes use the native tab transition and do not
fade artwork across surfaces. The 350 ms native focus and keyboard sizing
animation remains separate from character rendering. Saving and navigation never
wait for character animation. Saved feedback means local capture only; it does not
imply analysis or backup completion. Recovery is not a success state.

## Lifecycle and accessibility

Only an eligible visible root may play. Stop playback when hidden, covered, in
the background, under Reduce Motion, in Low Power Mode, or at serious or critical
thermal state. Show the matching static pose when animation is stopped or
unavailable. VoiceOver ignores decorative art; native status text carries
meaning. Preserve native controls, keyboard behavior and scrolling, and never
communicate saved or error status through color or motion alone.

## Validation status

Simulator motion and reference checks passed. Final native source `c0623c3`
passed 523 tests with 0 failures and 1 expected interactive sign-in skip;
the isolated cold-load regression/lifecycle run passed 47 checks, and the final
light/dark capture journey passed after that fix. The complete UI suite passed
37 tests with 0 failures/skips at `6707440`, before the isolated cold-load change.
The private draft is [#17](https://github.com/yakov103/mivu/pull/17). Physical
frame pacing, energy, thermals and manual phone acceptance remain pending.
