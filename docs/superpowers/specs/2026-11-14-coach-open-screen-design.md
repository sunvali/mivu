# Coach on the open screen (iPhone Duo) — design

Date: 2026-11-14. Status: draft for owner approval.
Code baseline: `origin/main` at `97731611` (iOS 1.3.0 plus two fixes). The Duo
code is on `main`; the `codex/mivu-icon-wordmark` working tree does not have it.

## Intent

Mivu 1.3.0 already fills the Duo, splits Today and Progress sideways, shows
today's log beside the Coach chat, and has a table pose. The owner uses a Duo
daily and named three things that still annoy them:

1. Sideways in Coach, tapping a logged meal slides its detail **over the chat**,
   while the right pane keeps showing Today. You lose the conversation to look
   at one meal.
2. Sideways, the Diary tab is one narrow column in the middle of a wide screen.
3. Logging a meal while reading a recipe or menu in another app means switching
   apps. Mivu has never been tried in the Duo's two-apps-side-by-side mode.

The pattern to borrow comes from AI chat apps on the Duo (Claude's artifacts):
what the chat produces opens **beside** the conversation, not over it.

The work must pass two bars equally (owner's decision): the owner notices it in
a week of real use, and it shows well in one screenshot or short clip.

## Owner decisions

- **Scope:** "Coach on the open screen". The side pane beside the chat shows
  what the conversation is about, not only Today.
- **The chat is on the right, the side pane on the left.** This reverses the
  1.3.0 layout (chat left, today's log right) and applies sideways flat and in
  book pose. Table pose and the other tabs keep their current arrangement.
- **Upright rule stays.** Unfolded and held upright is the normal one-column
  app. Nothing in this project splits the upright screen. Upright, a tapped
  meal slides over the chat exactly as today.
- **Pane control: automatic on changes, tap for the rest.** When Coach logs or
  edits something, the pane jumps to where it landed. For questions, the reply
  offers a button and the pane changes only on tap.
- **A full-screen button on the pane.** It expands the pane to the whole screen
  and back, without rotating the phone.
- **No comparison view** (two weeks or two meals side by side) in this version.
- **Other apps: test half width only.** Try Mivu in system Split View beside
  another app and fix what breaks. Dragging text or photos into Coach is a
  later project.

## Builder's calls (made during brainstorming, owner may override)

- **Diary sideways** gets two columns in the same shape as Today: the week
  strip and the day's summary on the left, that day's meals and workouts on the
  right. Diary is one screen (week strip above the chosen day), not a list that
  opens a detail, so this is a reflow, not a new selection model. The owner
  named the annoyance; the shape is my call.
- **What the pane can show:** Today (the default, as now), another day's log, a
  meal's detail, a workout's detail, or Progress. One value decides it.
- **Getting back:** Today is the root of the pane and everything else is pushed
  on top of it, so the system back button (titled "Today") returns to it, and a
  detail that closes itself (a deleted meal) lands on Today. A change Coach
  makes to today also brings Today back, with the existing highlight.
- **Automatic jumps** come from the latest turn's committed receipts
  (`CoachCommittedReceipt` carries `dayID`, `targetLocalDate`, `mealID`,
  `workoutID`, `weightID`), so no lookup is needed:
  - meal or workout whose `dayID` is the active day → Today, changed row lit
    (as now);
  - meal or workout on another day → that day's log (`targetLocalDate`), with
    no row highlight in this version (the highlight only exists for the live day);
  - weight added or corrected → Progress.
  Only receipts that appear during this session cause a jump. Opening the app,
  or paging back through old conversation, never moves the pane.
- **No jump while editing.** If a sheet or edit is open in the pane when a
  change commits, the jump is skipped, not queued; the receipt in the chat is
  still there to tap. How the pane reports "editing" is the builder's choice.
- **Another day in the pane is the normal Diary day**, with its usual add and
  edit controls, not a read-only copy.
- **Progress in the pane shows Pip still or not at all**, like Today in the pane.
- **Tap targets** reuse what the chat already draws: receipt cards, meal chips
  and quotes set the same selected record as today, and the existing "See
  today" / "See progress" buttons on the latest reply open in the pane when
  sideways instead of switching tabs. "See today" is hidden sideways only while
  the pane already shows Today.
- **Buttons for questions** ("how was my week?"): when Coach reads progress or
  another day's meals to answer, the latest reply gets "See progress" or "See
  that day". These reads leave no receipt, so this needs one small in-memory
  signal from `CoachEngine` to the view model, keyed by turn. That is allowed;
  "no new data" below means nothing new is stored. It is remembered for the
  current session only. After a relaunch the button is gone and the user asks
  again. Mark it in code as a known shortcut.
- **One selection, two presentations.** A meal opened in the pane becomes the
  normal pushed screen when the phone turns upright or closes, and returns to
  the pane when it turns sideways again. Open a meal while closed, unfold and
  turn, and it is beside the chat.
- **Expanded pane** covers the chat and composer and lays out like the matching
  full screen sideways (Today and Progress in their two columns), following
  the same crease rules as that screen in book pose. The chat stays mounted
  underneath, hidden, so its position and draft survive. The same button
  collapses it. Rotating upright while expanded returns to the normal upright
  app.
- **Table pose** (half-open on a table) is unchanged: no side pane.
- **Swapping sides must not cost the chat its place.** `DuoSplit` keeps the
  first pane mounted while the second comes and goes, and today the chat is the
  first pane. With the chat on the right it must still be the one that stays
  mounted when the phone turns upright, so scroll position and draft survive.
  The chat then sits next to the system's control strip on the right edge;
  `CoachView` currently ignores the trailing safe area on the assumption that
  the strip is on the far page, and that must be revisited.
- **The pane stays live:** if Coach corrects the meal that is open in the pane,
  the detail updates in place. Manual edits in the pane keep working, so Coach
  edit parity holds.

## Goals

1. Sideways in Coach, tapping a meal, workout or follow-up button never covers
   the chat; the result opens in the side pane and the composer stays usable.
2. Coach's own changes show where they landed, including on other days and for
   weight.
3. The pane can be expanded to full screen and collapsed with one control.
4. Sideways Diary uses the whole width in two columns.
5. Mivu is usable at half width beside another app: chat, composer with the
   on-screen keyboard, camera, sheets and all four tabs.
6. Folding, unfolding and rotating keep the pane's content, the chat position
   and the draft.
7. Upright, the outer display and every non-Duo iPhone behave exactly as today.

## Non-goals

- Comparison views; drag and drop into Coach; spoken replies; hinge-angle
  effects; an overhead plate camera; a capture-first closed mode; sidebar
  navigation.
- Persisting what Coach read with each turn.
- Android (decoupled from `ios/`), iPad, Hebrew.
- New Coach tools, prompts or data. This is presentation and routing only, and
  analysis stays separate from meal calculations.

## Anti-goals (failure even if it "works")

- The pane changing by itself after a question, or while the user is editing
  in it. An open manual edit must never be replaced or lost by an automatic jump.
- Any split while upright.
- A second Pip rig mounting in the pane (today the pane's Pip is a still image
  so the rig mounts once; Progress brings its own companion and must respect that).
- An update loop or rising CPU after rotating or folding (this happened once in
  the crease split).
- Losing the chat position, draft or an in-flight capture when the pane changes.

## Constraints

- AGENTS.md Coach rules: bounded owner queries, no rebuilt `DiarySnapshot`, the
  100-exchange window untouched, committed receipts immutable, the native glass
  "Jump to latest" button owned by `CoachTimelineTable`.
- Prefer platform APIs and the existing `DuoSplit` / `DuoBeside`; no new layout
  system and no dependency.
- Dynamic Type, VoiceOver, reduced motion and 44-point targets in every pose.
  At accessibility text sizes sideways already falls back to one column; then
  the pane does not exist and everything behaves as upright.
- VoiceOver focus stays in the chat when the pane changes automatically; the
  change is announced.
- Failing test first; native checks with XcodeBuildMCP on the iPhone Duo
  simulator; record the exact SHA. Test typing with the on-screen keyboard,
  walk all tabs through all rotations, and check CPU after layout changes.
- Feature branch from `main` and reviewed PRs; no mention of tools in commits.

## Where it lands (current code on `main`)

- Root tabs and the Coach pane: `DiaryRootView.rootTabs` in
  `ios/Mivu/Diary/TodayView.swift` (`DuoBeside { CoachView } secondary: {
  TodayView(isLiveDay: true) }`).
- Record taps: `CoachView.selectedRecord` and its `navigationDestination`
  (`MealDetailView`, `WorkoutDetailView`) in `ios/Mivu/Coach/CoachView.swift`.
- Follow-up buttons: `CoachReplyLines.followUps(for:)` and the "See today" /
  "See progress" buttons in `CoachView`.
- What Coach read: `CoachCommand.progress` and `.meals(date:)` in
  `ios/Mivu/Coach/CoachTools.swift`.
- Changed-row highlight: `DuoLayout.changedMeal` and `TodayView.isLiveDay`.
- Diary: `HistoryView` in `ios/Mivu/Diary/HistoryView.swift` (week strip plus
  `DaySections`), currently capped by `duoReadableWidth(evenWhenWide: true)`.
- Progress: `DiaryProgressView` in `ios/Mivu/Progress/ProgressView.swift`.
- Layout helpers: `ios/Mivu/Design/DuoLayout.swift`.

## Left to the builder

- Where the pane's state lives so both `CoachView` and the root's secondary
  pane can read it.
- How another day's log is shown in the pane (reusing `HistoryView` with a
  starting date is the obvious route).
- The expand control's design, following Apple HIG and the app's existing
  toolbar style. (Returning to Today is the system back button.)
- PR split. Suggested: (1) pane routing, automatic jumps and "Today" button;
  (2) expand button; (3) Diary two columns; (4) half-width check and fixes.
- Half-width testing method. If the simulator cannot put two apps side by side,
  report that check as blocked and hand the owner a short list to try on their
  own Duo; do not count it as passed.
- If the half-width check finds something large (a screen that needs a
  redesign), stop and report it instead of fixing it inside this project.
