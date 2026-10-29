# iPhone Duo support — design

Date: 2026-10-29. Status: draft for owner approval.

## Intent

The iPhone Duo (Apple's foldable, on sale 2026-10-23) has a 5.4″ outer display
(compact width, like any iPhone) and a 7.6″ inner display (regular width and
height, ignores the app's orientation lock). Mivu is iPhone-only, portrait-locked
and built with the iOS 27.0 SDK, so on the inner display it opens as a centered
window inside black bars. The owner wants Mivu to feel made for the Duo: no
black bars, and real use of the wide screen when it is turned sideways, in the
patterns the best launch apps use (Apple Music, Health, Things 3, Slack,
SmartGym, NYT Cooking).

## Owner decisions

- **Unfolded and held upright = the normal app.** Same single column, same
  bottom tab bar, full screen. No split views while upright. (The owner rejected
  the first mockups for splitting the upright screen.)
- **Unfolded and turned sideways** uses all four researched options:
  - **C · Sidebar:** the tab bar becomes a left sidebar (Today, Diary, Progress,
    Coach). Same four destinations, same order.
  - **A · Two-column Today:** Today's stacked cards flow into two columns, with
    the day summary (energy, macros, weight, Pip's note) on the left and meals
    plus "Add meal" on the right.
  - **B · Coach beside a live day:** the Coach destination shows the chat on the
    left and today's log on the right. A row that Coach just created or changed
    is highlighted as it lands.
  - **D · Half-folded meal snap:** with the phone propped half-open on a table,
    the camera preview sits on the upright half and the shutter plus Pip's prompt
    on the flat half.
- "Do all": everything ships in this project, and the owner authorized
  upgrading Xcode and downloading the iOS 27.1 simulator runtime.

## Builder's calls (made during brainstorming, owner may override)

- Diary and Progress follow the same sideways pattern, because the owner chose
  "do all": Diary shows the day list | the chosen day, and Progress reflows its
  sections into two columns.
- "Sideways" means the window is wider than it is tall, measured from the
  window geometry. Size classes can't tell upright from sideways on the inner
  display (it is regular/regular either way), and Apple's guidance splits only
  when the view is wider than tall.
- Columns split 50/50, so the fold falls in the gutter (Apple: split views
  divide evenly around the fold). The sidebar is the system one from
  `TabView`'s `.sidebarAdaptable` style; no custom bars, because the system
  moves only system bars to the vertical position.

## Settled after builder review (builder's calls unless marked as fact)

- **Fact:** relinking against the iOS 27.1 SDK alone removes the letterbox for
  Xcode-built apps. No Info.plist or scene opt-in was needed in published
  probes. The SwiftUI app lifecycle is already scene-based.
- **Fact:** there is no single "posture" API. Half-folded shows up as the fold's
  `.division` reserved region being active (`reservedRegions(kind:…)`), and
  UIKit's hinge interaction reports a partly open hinge. Apple also ships
  `ArrangementView` / `UIArrangementViewController` for splitting around the
  fold, plus `toolbarVerticalBehavior(_:)`. Prefer these platform APIs over
  hand-rolled geometry where they fit; Apple says arrangements must not sit
  inside a `List` or `ScrollView`.
- **Fact:** the Duo simulator has Closed / Book (127°) / Open poses and rotation
  through Device Hub, but no `simctl` or XCUITest pose control. Pose changes are
  checked by driving Device Hub, plus unit tests of the layout decision.
- **Three PRs in this one project**, in order: (1) Xcode 27.1 toolchain + full
  screen (upright and sideways single column, with continuity); (2) sidebar plus
  the two-column layouts (A, B, Diary, Progress); (3) half-folded meal snap (D).
  Each is reviewed and verified on its own; hosted CI is Linux-only, so there is
  no Xcode pin to change.
- **B's right column reuses Today's existing view and `DiaryViewModel`**. It
  adds no Coach query consumer and doesn't touch the 100-exchange window. The
  "just changed" highlight uses the existing `captureReceipt` / saved-meal ID
  signals; if those can't identify the row, highlight the whole day card rather
  than add a data path.
- **Continuity:** keep one stable view tree and vary only the layout; selection,
  draft and capture state already live in the models. Root-level sheets stay
  attached at the root. The system camera picker is allowed to be the one
  exception: if the system dismisses it on a fold, no photo is lost, and the user
  returns to where they were.
- **Sidebar:** the system `.sidebarAdaptable` tab view, only when sideways.
  `profileControl` stays in each destination's toolbar. Coach routing
  (`navigationRequest`, `openToday`, `selectedTab`) is unchanged. Inner columns
  are plain stacks, not a nested `NavigationSplitView`.
- **Progress sideways** reflows its existing sections into two columns. There
  is no new selection model, so it stays layout-only.
- Upright inner display caps content at a readable width (about 700 pt).

## Goals

1. No black bars on the inner display in any pose (needs the iOS 27.1 SDK).
2. Upright inner display: identical hierarchy and layout to the outer display,
   at full width with a readable content width.
3. Sideways inner display: sidebar navigation plus the two-column layouts above.
4. Half-folded: the meal-snap layout for photo capture.
5. Continuity: folding, unfolding or rotating keeps the selected destination,
   the selected day, scroll position, any open sheet, the Coach draft and
   in-flight capture. No reload and no lost input.
6. The outer display and every non-Duo iPhone behave exactly as today.

## Non-goals

- iPad support (`TARGETED_DEVICE_FAMILY` stays 1).
- Android (it is decoupled from `ios/`).
- Table-pose layouts for screens other than photo capture.
- Hebrew/RTL work beyond what exists (the MVP is English-only).
- New features, data or Coach behaviour. This is layout only, and analysis
  stays separate from meal calculations.

## Anti-goals (failure even if it "works")

- Any split or sidebar while the phone is held upright.
- The Coach tab disappearing or moving, or the structure differing between
  displays (Apple: keep the hierarchy the same on both screens).
- Losing your place, draft or capture on fold or unfold.
- Text or controls sitting on the fold, cramped columns, or anything below
  44-point touch targets.
- Custom tab, navigation or toolbars that the system can't relocate.

## Constraints

- Build with the iOS 27.1 SDK (Xcode 27.1, final release 2026-10-15). The
  deployment target stays 26.0.
- Verify on the iPhone Duo simulator (iOS 27.1 runtime, an on-demand download).
  StandBy and most extensions are unavailable in that runtime.
- Keep the Coach timeline rules in AGENTS.md (bounded owner queries, the
  native glass "Jump to latest" button owned by `CoachTimelineTable`).
- Dynamic Type, VoiceOver, reduced motion and 44-point targets in every pose.
  At accessibility text sizes, a sideways screen may fall back to one column.
- Repo workflow: a feature branch and PR, failing test first, native checks
  with XcodeBuildMCP, and the exact SHA recorded in a verification note.

## Where it lands (current code)

- Root tabs: `DiaryRootView.rootTabs` in `ios/Mivu/Diary/TodayView.swift`
  (a `TabView` with four `Tab`s, each in a `NavigationStack`).
- Today: `TodayView` (same file). Coach: `CoachView`
  (`ios/Mivu/Coach/CoachView.swift`). Diary: `HistoryView` / `DayHistoryView`
  (`ios/Mivu/Diary/HistoryView.swift`). Progress: `DiaryProgressView`
  (`ios/Mivu/Progress/ProgressView.swift`).
- Camera: `CameraCapture` wraps `UIImagePickerController`
  (`ios/Mivu/Diary/PhotoCapture.swift`). The system picker can't be laid out
  across the fold, so **D needs Mivu's own camera view (AVFoundation)**, used
  only in the half-folded pose. Every other pose keeps the system picker.
- Orientation: `INFOPLIST_KEY_UISupportedInterfaceOrientations` in
  `ios/Config/Shared.xcconfig`. It stays portrait for the outer display; the
  inner display ignores it.

## Left to the builder

- Confirming the half-folded signal against the 27.1 SDK headers (see above).
  If it isn't public, stop and report D as blocked rather than guessing from
  sensors.
- How the "just changed" highlight in B is driven, using the existing Coach
  receipt or commit signal, not a new data path.
- Column breakpoints at large Dynamic Type sizes.
- Test shape: a small unit test for the wide/upright decision, plus focused UI
  tests on the Duo simulator for upright, sideways and the fold transition.

## Fold-aware modes (owner request, 2026-10-30)

The owner asked for real benefit when the Duo is folded part-way. Posture comes from the fold's
division reserved region (`GeometryProxy.reservedRegions(kind: .division)`): an upright crease is
**book**, a level crease is **table**, no active crease is **flat**.

- **Fold-aware splits:** every two-pane screen (Coach beside the live day, Today, Progress) uses one
  `DuoSplit` that sizes its panes to meet exactly at the crease. It is built from stacks, not
  `ArrangementView`, so the primary pane keeps its identity and scroll position across poses.
- **Coach at the table:** the conversation stays on the standing half; Pip, starters, the field, camera
  and mic move to the flat half.
- **Progress at the table:** range picker and chart on the standing half, the rest scrolls below.
- **Table camera:** Coach's camera puts the preview on the standing half and the controls on the flat
  half, stays open for several plates (up to 8) until Done, and offers a 3-second timer.
- The earlier sample-mode tabletop camera is removed; Coach's camera is the real capture path.
- Not built: snapping by voice, and showing Pip's estimate inside the camera. Coach estimates after Done.
