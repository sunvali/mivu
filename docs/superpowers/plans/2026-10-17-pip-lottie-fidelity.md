# Pip Lottie Fidelity Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans for the core implementation, with available subagents for mechanical work and independent review. Preserve the owner's model preferences; unavailable workers must not stall authorized work.

**Goal:** Replace the rejected Rive implementation with a detailed Lottie Pip and actual Today/Coach compositions matching the approved PDF.

**Architecture:** Preserve renderer-independent diary events, motion arbitration and character selection. Replace the asset/player boundary with one bundled Lottie player and reference-derived detailed fallbacks. Rebuild the two existing screen compositions against the original artwork, keeping native interaction and accessibility.

**Tech Stack:** Swift 6, SwiftUI, iOS 26+, official Airbnb Lottie iOS, Swift Testing/XCTest, XcodeBuildMCP.

**Spec:** `../specs/2026-10-17-pip-lottie-fidelity.md`. The owner explicitly authorized this correction against the already-approved PDF; no new visual direction is being proposed.

## Global Constraints

- The original PDF/reference/storyboard/context are authoritative; the rejected vector approximation is not reused.
- Match the illustrated screen composition; the old 64/40-point interpretation is superseded by the owner's visual-fidelity correction.
- One active player; local resources only; no expressions or per-frame SwiftUI publication.
- Preserve records, local-save/backup semantics, drafts, keyboard and Coach reading position.
- Only Pip ships; keep future bundled character selection.
- Use XcodeBuildMCP for serial native jobs, UUID-isolated synthetic fixtures, and nonzero named evidence. Never reset the owner's diary.
- No merge. Draft delivery precedes physical-phone profiling as requested.
- No prohibited terms in PR or commit prose. Use `rtk` for verbose shell output and Headroom when available.

## Review Focus

- Original shaded art can be damaged by clipping/part seams; compare actual rendered contours and moving joints against source at large and app sizes.
- A working JSON/marker contract can conceal poor movement; inspect native gesture recordings, repeated reactions and interruption frames.
- Larger Today/Coach placement can cover records/actions; verify rows are fully tappable and composers remain reachable at default/system-largest text.
- Backgrounding or replacement during playback/loading can revive stale work; preserve generation and lifecycle tests on the actual player.
- Reference data is illustrative; real empty/offline/error/long-text states must remain truthful, readable and usable.

## Task 1: Reference-derived Lottie artwork and native preview

**Files:** `design-system/mivu/characters/pip/lottie-source/`, `ios/Mivu/Resources/Characters/pip/`, Xcode package integration, `ios/MivuTests/CompanionLottieAssetTests.swift`.

**Interfaces:** Named Lottie clips/markers for resting, blink, attentive, thinking, saved, reviewed, recovery and greeting, with a validated local artwork manifest. Preserve original source images/hashes. Later tasks consume the validated animation and fallback paths.

- [ ] Write an actual-asset test requiring a decodable bundled animation, the named clips and supported Core Animation playback; run it and observe missing-asset failure.
- [ ] Pin verified official Lottie runtime and bundled license, preserving unrelated package resolution.
- [ ] Author detailed reference-derived image layers and vector masks plus actual joint animation; render resting and greeting in a native preview.
- [ ] Inspect side-by-side with PDF pages 1–3; correct face, silhouette, shading, proportions and seams before continuing.
- [ ] Complete all named clips, timings and detailed static fallbacks; inspect moving and held poses in both appearances. Run actual-render tests and commit the tested asset/source/package.

## Task 2: Lottie runtime replacement

**Files:** `CompanionRuntime.swift`, `CompanionView.swift`, `CharacterCatalog.swift`, associated selection/runtime/root tests and package/resources.

**Interfaces:** Retain `select`, `attach(eligible:)`, `apply(_:darkMode:)`, `stop`, `isReady` and `loadFailed`. Descriptor uses renderer-neutral animation resource path. One player maps semantic poses and fresh reaction IDs to named Lottie segments; held poses are static and appearance changes do not replay reactions.

- [ ] Adapt meaningful renderer tests before replacing internals: repeated same-kind reactions advance and settle; pause before first frame drops stale feedback; hidden/stale load and obsolete-view teardown cannot revive a player.
- [ ] Observe expected RED, replace Rive internals with the actual Lottie player, and remove Rive from the shipping package/resources.
- [ ] Preserve cancellation, one-attempt attachment retry and identity guards. Verify static policy loads no playing view.
- [ ] Run catalog/selection/policy/presentation/receipt/root/actual-player tests; inspect real frames and commit.

## Task 3: Match Today, Coach and Settings to the approved compositions

**Files:** `TodayView.swift`, `CoachView.swift`, `SettingsView.swift`, `DiaryStyle.swift`, design-system notes/tokens and affected UI tests.

**Interfaces:** Existing authoritative view models and state remain. Today uses the prominent character/intake arrangement from context; Coach uses the seated companion/status and horizontal composer. The animated character does not own navigation, data or focus.

- [ ] Add/adjust journey checks for fully revealed Today meal rows, typing/Send, saved/reviewed/detail return, offline/error states and actual system largest text.
- [ ] Rebuild the normal-size compositions from page 2; preserve truthful state and accessible adaptive layout.
- [ ] Capture paired actual screenshots with comparable synthetic content; compare scale, spacing, typography, color, materials, iconography and character against the source image. Fix discrepancies.
- [ ] Verify affected UI suites, 50 tab changes, focus/reading preservation and fallback capture/review; commit.

## Task 4: Simulator fidelity acceptance and private draft

**Files:** `docs/verification/2026-10-17-pip-lottie.md`; native screenshots/recordings in the primary workspace output directory.

- [ ] Run complete native scheme coverage, retain exact source/environment/counts and correct any failure with scoped RED/GREEN evidence.
- [ ] Inspect default/system-largest, light/dark, reduced motion, contrast/transparency, cover/offscreen/background behavior and interrupted/repeated reactions. Save a usable native recording and visual comparisons.
- [ ] Obtain independent whole-branch review, fix blocking findings and verify changes. Keep physical-device performance, haptics, VoiceOver/camera/provider acceptance explicit.
- [ ] Commit evidence, push through required hooks, create/attach a private draft against the correct live base, verify hosted checks, and leave the simulator preview open for review. Tell the owner it is ready for the iPhone test.

## Motion revision acceptance

- Replace held frames with seamlessly closing, restrained body-part loops.
- Slow actions and synchronize presentation expiry with authored marker lengths.
- Keep all Coach reactions on its seated rig; smooth source-pose transitions.
- Verify actual native pixels and frames advance during rest and quiet typing,
  remain uninterrupted by appearance updates, and stop while hidden/static.
- Record and inspect real simulator motion, including a complete idle cycle and
  repeat gestures, before publishing the draft review.
