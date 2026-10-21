# Dynamic Island day progress — verification

- **Source:** `feat/dynamic-island` at `b412cac` (UI checks at `f548586`). The branch is based on `feat/widget` at `319bd0a`.
- **Environment:** Xcode 27.0, iOS 27.0 simulator "Mivu dynamic-island (Claude)", an iPhone 18 Pro
  (`CEE1F6BE-3EFA-4913-99FA-BB33D802BA93`), on this machine only. XcodeBuildMCP wasn't available in
  this session, so `xcodebuild` ran directly.
- **Spec / plan:** `docs/superpowers/specs/2026-10-21-dynamic-island-design.md`,
  `docs/superpowers/plans/2026-10-21-dynamic-island.md`

## Automated

| Run | Revision | Result |
|---|---|---|
| `MivuTests` (whole unit target, test plan `Mivu`) | `b412cac` | 1,024 tests in 95 suites passed |
| `MivuTests/DayProgressActivityTests` + `WidgetSnapshotTests` | `b412cac` | 23 tests in 2 suites passed |
| `MivuTests` after rebasing onto `main` at `1d16ec8` | `c53cc09` | 1,068 tests in 101 suites passed |
| `build-for-testing`, including `MivuUITests` | `243fb9f` | TEST BUILD SUCCEEDED |

**Not run (blocked by the owner's instruction):** `MivuUITests/LiveActivityUITests.testDynamicIslandTogglesShowAndPersist`.
The owner asked not to spend time running UI tests. It compiles but has not been run, so it is not
counted as evidence.

## Manual, on the simulator

Launched with `--diary-ui-test <id> --live-activity --live-activity-sample <kcal> --diary-history-fixture`.
`--live-activity-sample` is a DEBUG-only argument that sends a full day with targets, because the
synthetic diaries have none.

| Check | Result | Evidence |
|---|---|---|
| Compact: Pip on the leading side, figure on the trailing side, "over" in neutral grey | Pass | `dynamic-island/compact-over.png` |
| Expanded: Pip and ring the same size around a centered figure; three equal macro columns; nothing clipped | Pass | `dynamic-island/expanded-over.png` |
| Lock Screen mirrors the expanded layout | Pass | `dynamic-island/lock-screen-over.png` |
| Settings: "Show in Dynamic Island" plus "Hide numbers on Lock Screen" shown only while it is on | Pass | `dynamic-island/settings.png` |
| Real diary data (no target, unknown macros) shows "100 eaten" with dashes, never "0g" | Pass, after the fix in `f548586` | Earlier build showed "P 0g", now covered by `unknownMacroIsNeverZero` |
| The first build's Pip (489×592 asset) rendered as a grey box in the island | Fixed with a 138×168 `PipIsland` cut | `dynamic-island/expanded-under-before-inset.png` |
| An activity starts on app open and updates when the diary loads | Pass (unified log: start, then update) | — |

## Review fixes (`b412cac`)

- If any item's calories are unknown, the figure shows "–", never a full "2,000 left" (`unknownCaloriesNeverShowAFullTarget`).
- Only active or stale activities count as running, so a new one starts after iOS ends the old one at about 8 hours (`onlyActiveOrStaleActivitiesCountAsRunning`).
- When numbers are hidden on a locked phone, VoiceOver says "Mivu day progress" instead of the figures, and the left/over caption is hidden too. This was not checked on a device.

## Later change

- The onboarding offer was removed at the owner's request. The island is now enabled only from Settings, and it is off by default.

## Not verified

- Hidden numbers on a locked device (`privacySensitive`). The simulator showed iOS's first-run
  "Allow Live Activities" prompt, which was left for the owner, and redaction was not captured.
- The stale state after the cutoff, the largest Dynamic Type size, VoiceOver reading, tapping
  through to Today, and the iOS-Settings-off state of the toggle.
- A physical device.
