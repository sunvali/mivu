# Pip authoring handoff

Pip is an original orange fox with a cream muzzle, chest and tail tip, brown eyes and paws, and a teal scarf. The approved concept is `reference.png`; the shipped small-size vector interpretation is authored in `source/geometry.py`. No stock character, font, audio, texture, script, or remotely loaded asset is bundled.

## Editable source and reproduction

The complete editable rig is `source/scene.rml` (Rive Markup Language). `source/geometry.py` contains the original curves, while `source/build_pip.py` generates the layered rig, animation keys, data bindings and matching vector fallback PDFs. `paths.py` parses the restricted curve syntax. Source stays outside the application bundle.

Use Python 3 with ReportLab, and official Rive CLI **1.6.0**. From the repository root:

```sh
python3 design-system/mivu/characters/pip/source/build_pip.py
rive design-system/mivu/characters/pip/source --verify --format=json
rive design-system/mivu/characters/pip/source --once
cp design-system/mivu/characters/pip/source/build/mivu-companion.riv ios/Mivu/Resources/Characters/pip/mivu-companion.riv
```

The macOS arm64 CLI archive is available at `https://releases.rive.app/cli/v1.6.0/rive-macos-arm64.tar.gz`; verified SHA-256: `ac0f7a3de688b177577835834fb8f456e1349e8fc0c65984acc6e80429e2b7d6`. The tool is a development dependency, not part of the app. Local script-free `--once` export required no account or signing. Publishing through Rive services or exporting an editor `.rev` is a separate workflow with its own account/plan requirements; neither was used here.

Keep `build_pip.py` and `scene.rml` synchronized. To make direct RML edits permanent, incorporate them into the generator before regenerating. Regenerate the manifest checksums after an intentional asset change. ReportLab may change PDF metadata on regeneration; visual content is the acceptance criterion for static exports.

## Runtime contract

- Runtime: official `RiveRuntime` **6.28.1**, pinned by Swift Package Manager; its MIT notice ships separately. The adapter uses the supported synchronous `RiveView` renderer and its exact bound typed model instance. Sequential native tests exposed skipped reactions in the concurrency renderer; the compatibility path preserves the same asset contract without a runtime fork or duplicate triggers. See `docs/verification/2026-10-17-pip-runtime.md`.
- Artboard: `MivuCompanion`, 512 × 512, transparent, shared bounds for every pose.
- State machine: `Companion`; default bound model: `CompanionModel`, exported instance `Default`.
- Number `pose`: integer 0–6, default 0. Boolean `darkMode`: default false. Trigger `react`: initially un-fired.
- Pose values: resting 0, attentive 1, thinking 2, saved 3, reviewed 4, recovery 5, greeting 6.
- Set pose and appearance before firing a fresh reaction. A plain rest update never blinks. A new rest reaction blinks for 150 ms; host schedules this no more often than every 12 seconds.
- Saved 450 ms, reviewed 650 ms, greeting 700 ms include their settle to rest. Thinking loops over 1.4 seconds. Attentive settles over 150 ms; recovery over 200 ms.
- A separate appearance layer changes vector colors without resetting the gesture. Shared keyed defaults restore every articulated part on interruption.
- Reduced motion, low power and constrained thermal policy use the matching static pose. Hidden/covered/background surfaces stop advancement. No frame callback changes application state.

## Preview and validation

Example real-runtime render (Metal access may be needed on macOS):

```sh
rive design-system/mivu/characters/pip/source --screenshot=/tmp/pip-reviewed.png --data=pose=4 --data=react=1 --advance=300ms
rive design-system/mivu/characters/pip/source --screenshot=/tmp/pip-thinking-dark.png --data=pose=2 --data=darkMode=true --advance=600ms
```

Inspect every pose in both appearances, at actual 40 pt and 64 pt app sizes. Check the full gesture and settle, repeated fresh actions, interruptions, dark-mode changes, Reduce Motion, covering sheets, and foreground/background transitions. Run `CompanionAssetTests` against the actual bundled file; typed bindings alone are not proof of visible motion. Simulator evidence does not establish physical-device frame time, power consumption, or thermal behavior.

## Ownership and handoff

The production curves and gesture keys were created specifically for Mivu from its selected concept; no third-party artwork was copied or imported. The project retains these editable sources and runtime exports. Concept-image provenance remains in `asset-manifest.json`. Rive tooling/runtime licenses do not grant ownership of third-party character artwork; this asset has no such imported artwork dependency.
