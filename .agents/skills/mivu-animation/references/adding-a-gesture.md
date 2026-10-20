# Adding a gesture, a moment, or a rig part

Run commands from the repository root. Gestures are pure data; nothing here needs
per-frame code.

## How a gesture is built

A `PipGesture` is a list of keys `(at, pose)`. Each key is the full pose Pip
arrives at by `at` seconds; unlisted joints rest. Build keys with the builder in
`ios/Mivu/Design/PipGesture.swift`:

- `$0.at(time) { pose chain }` starts from `.rest` and chains helpers.
- `$0.settle(at:)` returns to rest. One-shots must end in `.rest`.
- `$0.end(in: .curled, at:)` ends in another body set (only `curl-up` / `wake`).
- Helpers (degrees; +nod is down): `nod`, `tilt`, `earPerk(_, .left/.right/.both)`,
  `pawUp(_ side, _ degrees, elbow:)`, `hop`, `squash` (keep <= 0.10), `tailWag`,
  `scarf`, `eyes(.open/.half/.closedHappy/.closedSleepy/.wide/.heart)`,
  `mouth(.closedSmile/.smallOpen/.bigOpen/.o/.concerned/.yawn)`, `look(x, y)`,
  `turn`, `blushing()`, `hearts(count, drift:)`.
- `PipGesture("name", loops: true) { ... }` repeats from its first key.

## Worked example: a "proud" gesture after a correction is reviewed twice

1. **Add the entry** to `PipGestureLibrary.all` in
   `ios/Mivu/Design/PipGestureLibrary.swift`:

   ```swift
   PipGesture("proud") {
       $0.at(0.10) { $0.squash(0.05).nod(3) }
       $0.at(0.30) { $0.hop(8).earPerk(14).eyes(.closedHappy).mouth(.smallOpen).tailWag(16) }
       $0.at(0.48) { $0.nod(-4).earPerk(10).eyes(.closedHappy).blushing() }
       $0.settle(at: 0.80)
   },
   ```

   Keep the hop at or under 14 and squash at or under 0.10 so feet land back on
   y 472. The name must be unique.

2. **If it is a new app event**, add it in four places:
   - `PipMoment` case in `PipGesture.swift`.
   - A duration in `MivuMotion.swift` (e.g. `static let proud: TimeInterval = 0.8`).
   - A `CompanionPose` case in `CompanionPresentation.swift`, plus a
     `CompanionEvent.Kind` case (its `pose` and `duration` switches) if it is a
     fresh-success signal. Fresh success
     (including affection/habit) ranks above processing and tap/pat; give it a
     deadline from `MivuMotion` and keep dedupe by profile/operation(/attempt).
   - A case in `CompanionRuntime.moment(for:tapLevel:hour:)` (the `isOneShot`
     list there needs no change for a one-shot).

   If it is only a new variant of an existing moment, skip this step.

3. **Map it** in `PipGestureLibrary.gesture(for:)`: `case .proud: return named("proud")`.
   Variants (hour of day, tap level) are chosen in this one switch.

4. **Tests run automatically.** `PipGestureTests` loops over
   `PipGestureLibrary.all`: it checks that each gesture ends at rest within two
   seconds, only `curl-up`/`wake` change the body set, squash and hop stay in caps,
   and every joint name exists in the standing set. It also checks that every
   `PipMoment` maps to a library gesture.
   Add a named test only for new behaviour: moment mapping in
   `PipGestureTests`, priority/dedupe in `CompanionPresentationTests`, runtime
   playback in `CompanionRigRuntimeTests`, a signal from a screen in
   `DiaryCompanionMomentTests`. Write the failing test first.

5. **Review it.** Launch the app with `-PipRigPreview`, play the gesture at 40, 64,
   88 and 200 pt in light and dark, and check that it reads and that Coach's
   seated set looks right.

6. **Record evidence.** Run the Swift suites in
   [verification.md](verification.md), then note source SHA, simulator, counts and
   any blocked check. Never claim a pass from a skipped or zero-test run.

## Adding a new part or face shape to `pip.svg`

Edit `design-system/mivu/characters/pip/rig/pip.svg`; see the SVG conventions in
the [rig README](../../../../design-system/mivu/characters/pip/rig/README.md).

1. Add `<g id="part-name">` holding exactly one direct `<path>` (absolute
   `M L C Q Z` only), with `fill` and optional `data-fill-dark`.
2. Set `data-pivot="x y"` at the joint. Nest it in its parent group, or use
   `data-parent` to draw it behind the parent. Use `-l`/`-r` for the viewer's
   side. Document order is z-order.
3. For a body part, add it to every body set (`data-set="standing|seated|curled"`)
   so all three have the same ids. Mark head parts with `data-view`
   (`right|front|left`); the left view is mirrored by `build.py`.
4. For a face alternative, add `data-shape="slot.name"` (for example
   `mouth.grin`); exactly one shape per slot is visible by default
   (`display="none"` on the rest). Then add the case to `PipPose.EyeShape` or
   `MouthShape` in `PipPose.swift` so gestures can name it.
5. Hidden extras (blush, hearts) use `display="none"` and are turned on by a pose.
6. Rebuild and check:

   ```sh
   .venv/bin/python design-system/mivu/characters/pip/rig/build.py --png /tmp/pip-png
   .venv/bin/python design-system/mivu/characters/pip/rig/test_rig.py
   ```

   Add mandatory new ids to `test_body_parts_present` in `test_rig.py` (and
   to `PipRigAssetTests` if the loader must require them). Keep `pip-rig.json` under 512 KiB
   (hard cap 1,048,576 bytes), then run `PipRigAssetTests`, `PipRigViewTests`,
   `PipRigSnapshotTests` and review the output in `-PipRigPreview`.
7. Refresh hashes and byte sizes in
   `design-system/mivu/characters/pip/asset-manifest.json`.
