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

Coach uses the same seated original painting in every semantic state, including
its static fallback. It does not use Today poses or a separately animated
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

Cross-dissolve semantic pose changes over 350 ms. The continuous loops have
closed, gradual movement so transitions do not feel jumpy. Saving and navigation
never wait for animation. Saved feedback means local capture only; it does not
imply analysis or backup completion. Recovery is not a success state.

## Lifecycle and accessibility

Only an eligible visible root may play. Stop playback when hidden, covered, in
the background, under Reduce Motion, in Low Power Mode, or at serious or critical
thermal state. Show the matching static pose when animation is stopped or
unavailable. VoiceOver ignores decorative art; native status text carries
meaning. Preserve native controls, keyboard behavior and scrolling, and never
communicate saved or error status through color or motion alone.

## Validation status

The 520-test native unit result is a baseline from before the latest continuous
motion changes. Verification of the latest motion source and runtime asset is
pending. Full UI validation, broader visual/accessibility review and
device-performance acceptance also remain pending. Do not treat simulator
results as evidence of device frame time, energy use or thermal behavior.
