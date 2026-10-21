# Mivu widgets design

## Intent

Let a user see today's calories at a glance and jump straight into the two
things they do most — photographing a meal and asking Coach — without hunting
for the app. It extends the Log Food shortcut (#30) to every system surface.

## Goals

- **Home Screen Small**: today's calories eaten of target as a ring, with a
  small static Pip pose. Whole widget opens the app on Today.
- **Home Screen Medium**: the same ring and Pip, plus two buttons: **Log Food**
  (camera) and **Coach** (opens the Coach tab).
- **Lock Screen**: `accessoryCircular` (ring, eaten number) and
  `accessoryRectangular` ("1,360 / 2,000 kcal"). Shown even while locked
  (owner's call).
- **Control Center control**: one-tap Log Food camera button (`ControlWidget`),
  also placeable on the Lock Screen and the Action button.

## Owner decisions

- Main figure is **eaten of target** ("1,360 / 2,000 kcal"); the ring fills with
  eaten ÷ target and caps visually at full when over.
- Data is the **currently selected profile** in the app.
- Calories are **not** redacted on a locked device.
- With no calorie target: show eaten only plus "Set a target". Before onboarding
  / no diary: Pip plus "Set up Mivu".
- Coach button opens the Coach tab, ready to type (no auto-focus, no dictation).
- Pip appears as a pre-rendered static pose (the Core Animation rig cannot run in
  a widget).

## Non-goals

Large / StandBy-specific layouts, macros, per-widget profile choice, configurable
widgets, Live Activities, Watch complications, Hebrew/RTL.

## Anti-goals

- A stale number: the widget must never show yesterday's total as today's, or
  calories from a profile that is no longer selected.
- The widget extension opening the diary database or holding credentials.

## Constraints and Apple practice

- iOS 26 target, SwiftUI WidgetKit extension; synchronized folders in the
  Xcode project.
- Data reaches the widget as a tiny Codable snapshot the app writes into an
  **App Group** container (`group.com.yakov103.mivu`): `day` (the active
  waking-day date), `eaten` kcal, `target` kcal (optional), `hasDiary`,
  `rolloverAt` (next day-start instant, computed in the app from
  `DayCutoff.hour`, default 4 AM), `writtenAt`. The extension never reads the
  diary database and never computes the day boundary itself.
- The app rewrites the snapshot and calls `WidgetCenter.shared.reloadAllTimelines()`
  whenever today's totals, the target, the selected profile or the active day
  change (including the automatic rollover). *Builder's call:* one hook in
  `DiaryRootView` keyed on `model.changeGeneration`, `model.selection` and
  `model.activeDay`, the same `.task(id:)` pattern already used for the morning
  recap, so every mutation path (Coach edits, restore, delete) is covered
  without touching each one. No selected profile or no diary → `hasDiary = false`
  → "Set up Mivu".
- Timeline: two entries: now, and `rolloverAt`. After `rolloverAt` the widget
  shows **0 / target** (owner's call) until the app writes a fresh snapshot.
- Buttons use App Intents only. Log Food reuses `LogFoodIntent`; a new
  `OpenCoachIntent` mirrors it and sets a pending "open Coach" request that
  `DiaryRootView` handles like the quick-log request (select the `coach` tab).
  Both intents are compiled into the app and the extension; with
  `openAppWhenRun` the system runs `perform()` in the app process. *Builder's
  call:* the in-memory request flag is enough. Prove a cold launch with a UI
  test, and move the flag into the App Group only if that test fails. The
  open-Coach request follows `openQuickLog()`'s guards: it is dropped during
  onboarding, a profile change or with no diary. The Coach tab handles a missing
  ChatGPT connection itself.
- *Builder's call:* extension bundle ID `com.yakov103.mivu.widgets`, its own
  xcconfig like the existing targets, App Group entitlement on both app and
  extension, and the privacy manifest checked for the extension.
- Rendering: `containerBackground(for: .widget)`, `widgetAccentable()` on the
  ring and Pip so tinted and clear (glass) modes look right; system font sizes,
  VoiceOver labels such as "1,360 of 2,000 calories eaten", 44-point buttons.
- English only. Synthetic data in previews and tests.

## Verification

- Unit test for the snapshot: written values match today's report; day mismatch
  reads as zero; no target → eaten-only state.
- UI test: launching the app with the open-Coach request lands on Coach.
- Widget previews for every family and empty state, inspected in light, dark and
  tinted; one simulator run adding the widget (coordinate simulator use — other
  agents share it).

## Left to the builder

Exact layout spacing, which Pip pose image, snapshot file name, ring stroke
width, how the request flag is shared between the two intents.

## Blocked / owner gates

App Groups on a physical device need the owner's signing team to register the
group in Xcode; simulator builds do not.
