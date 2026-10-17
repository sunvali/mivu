# Pip: character and motion bible

Status: approved original illustration and Lottie motion contract, 17 October
2026. Pip is the only launch companion. The approved source atlas is
`storyboard.png`; the editable rig and render details are documented in
[`lottie-source/README.md`](lottie-source/README.md). The approved PDF motion
guide remains the visual authority for acting and composition.

## Identity and composition

Preserve the original shaded illustration: orange fox, cream muzzle/chest/tail
tip, brown eyes and paws, and short teal scarf. Keep its face construction,
proportions, silhouette, scarf knot and direction consistent in all poses and
appearances. Do not redraw the character or flatten the full body into a
single moving image.

Today places a prominent full-body Pip beside intake below the date. Coach
places a seated companion above its compact horizontal composer. Native text,
keyboard, controls and navigation remain SwiftUI-owned. Keep feet grounded and
the illustration subordinate to meal content and readable controls. At larger
accessibility text sizes, preserve native text and scrolling instead of
shrinking labels or hiding actions.

Coach's seated figure comes from the exact original illustration crop in
`context.png`. It has its own resting and blink markers and static asset. Its
body, face, framing and scale stay sourced from that approved crop; only the two
registered eyelid patches come from the separate blink edit.

## Rig and acting

The 512×512 Lottie composition uses the original atlas through authored image
layers and vector masks. Head, ears, torso, paws, tail and scarf have separate
transforms where the source pose supports them. Core Animation renders motion;
SwiftUI does not publish frame-by-frame state. Static detailed PNGs provide
matching semantic poses for reduced motion and unavailable playback.

| Pose | Duration | Acting and meaning |
| --- | ---: | --- |
| Resting | held | Original open-eyed, four-foot stance; no idle bobbing |
| Blink | 150 ms | Close and reopen the painted eyelids after 12 eligible resting seconds |
| Attentive | 150 ms | Small head and ear settle; quiet while typing |
| Thinking | 1,400 ms | Restrained head, ear, paw and tail movement during actual processing |
| Saved | 450 ms | Small nod and open-paw acknowledgment for durable local capture |
| Reviewed | 650 ms | Brief grounded celebration after an explicit successful review |
| Recovery | 200 ms | Calm explanatory open paw while native text explains the issue |
| Greeting | 700 ms | One restrained wave with head, tail and scarf follow-through |
| Coach resting | held | Original seated Coach composition, still |
| Coach blink | 150 ms | Small registered eyelid patches close and reopen |

Use interruptible 100 ms pose transitions. Feet remain grounded, and secondary
motion settles within the action. Saving and navigation never wait for
animation. Saved feedback means local capture only; it does not imply analysis
or backup completion. Recovery is not a success state.

## Lifecycle and accessibility

Only one visible root may play. Hidden, covered, background, reduced-motion,
low-power and serious or critical thermal states stop decorative playback and
show the matching detailed static pose. Quiet typing remains still. VoiceOver
ignores decorative art; native status text carries meaning. Preserve native
controls, keyboard behavior and scrolling, and never communicate saved or
error status through color or motion alone.

## Validation status

The native unit suite passed 520 tests with 0 failures and 1 expected
interactive-authentication skip. Prior UI runs passed the new Coach composition
and largest-text checks. Full UI validation and broader visual/accessibility
review remain pending, as does physical-device performance acceptance. Do not
treat simulator results as evidence of device frame time, energy use or thermal
behavior.
