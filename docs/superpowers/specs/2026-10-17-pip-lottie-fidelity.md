# Pip Lottie fidelity correction

The owner rejected the Rive result and explicitly requested a restart using Lottie, reproducing the approved PDF 1:1. This supersedes the prior implementation's artwork, placement interpretation and renderer decisions. Implementation and simulator/draft delivery remain authorized; merging and physical-device performance acceptance do not.

## Authority

- `output/pdf/Mivu-Pip-Motion-Guide.pdf` in the primary workspace, SHA-256 `d1f2def8b63f3bc2dc809054cd3feb93ddbac38dd638267fcfa0021357d0f07c`.
- Character identity: `design-system/mivu/characters/pip/reference.png`, original orange fox, cream muzzle/chest/tail, brown paws/eyes, teal scarf. Preserve the original shaded illustration, facial construction, silhouette and anatomy. The rejected simplified vector drawing is not an acceptable source.
- Actual screen composition: `design-system/mivu/characters/pip/context.png`, PDF page 2. Today places a prominent full-body Pip beside intake, below the date; Coach places a seated companion above a compact horizontal composer. Match the illustrated relative scale, spacing, hierarchy, materials and controls in both appearances.
- Acting: `design-system/mivu/characters/pip/storyboard.png`, PDF page 3. Pages 4–6 govern timing and restrained motion; page 7 governs appearance and accessibility.

The old 64/40-point labels conflict with the much larger illustrated placements. The owner's explicit instruction to match what the PDF shows takes precedence: reproduce the illustrated composition at normal text size. At accessibility sizes, preserve readable native controls and scrolling rather than shrinking text or hiding actions.

## Artwork and animation

Use the original approved illustration pixels inside authored Lottie image layers and vector masks, with independent head/ears, torso, paws, tail and scarf motion. Keep an editable source recipe, source hashes and named timelines. No stock fox, regenerated identity, flattened replacement illustration, whole-image bobbing loop, or frame-by-frame slideshow may substitute for the character rig.

Start with a still full-detail pose and a real greeting, rendered by Lottie. Compare them directly against the source before app integration. Then complete resting/blink, attentive, thinking, saved, reviewed and recovery. Greeting 700 ms, saved 450 ms, reviewed 650 ms, attentive 150 ms, thinking 1,400 ms, recovery 200 ms; blink 150 ms after 12 eligible resting seconds. Use 100 ms interruptible pose transitions. Feet stay grounded; restrained secondary motion settles. Quiet typing remains still.

Use the official Airbnb Lottie iOS runtime, pinned to a verified release. Prefer supported Core Animation features; confirm the actual renderer and rendered output. No network images, expressions or per-frame SwiftUI state. Bundle all source art. Remove the Rive dependency and rejected production artwork from the shipping target.

## Behavior retained

Retain the tested catalog, local selection, semantic receipts, priority/expiry/dedup rules, cancellation and profile isolation where renderer-independent. Only Pip ships. A later compatible bundled pack enables Settings selection. One root owns at most one playing character; hidden, covered, background, Reduce Motion, low-power and serious thermal states stop decorative work and use a matching detailed static pose.

SwiftUI owns native controls, text, keyboard and navigation. Saving never waits for animation. Saved means durable local capture; reviewed means an explicit successful review. Keep error/retry and backup distinctions. Preserve diary records, drafts, reading position and capture haptics.

## Acceptance

1. Inspect the actual Lottie character at full size and app size against the PDF, including contours, face, shading, body proportions, scarf and all seven poses. Fix visual deviations before integration.
2. Compare actual simulator Today/Coach light/dark screenshots directly with page 2, using deterministic synthetic content. Inspect default and actual system largest text, keyboard, reduced motion, contrast/transparency, detail, sheet and background transitions.
3. Retain a usable native recording and inspect gesture frames and interruptions. Component tests and binding/marker checks do not establish visual fidelity or smoothness.
4. Run affected native regression checks and complete scheme coverage; preserve failed evidence and identify exact corrected-source results. No zero-test pass. Use XcodeBuildMCP. Physical Release frame, energy and memory budgets remain a separate pending gate until the owner's phone test.
5. Complete independent review and open a private draft PR only when the Lottie asset and simulator fidelity checks are reviewable. No merge.
