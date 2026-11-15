# Coach on the open screen: verification

Design: [spec](../superpowers/specs/2026-11-14-coach-open-screen-design.md).
Plan: [plan](../superpowers/plans/2026-11-14-coach-open-screen.md).

## Pull request 1: side pane, chat on the right

- App source: `39b520b8` on `feat/duo-coach-pane`, based on `main` `97731611`.
- Environment: Xcode 27.2 (27B52), iPhone Duo simulator, iOS 27.1 (24A94425),
  local run through `xcodebuildmcp simulator test` with the `Mivu` test plan,
  parallel testing off. Hosted CI is Linux only and does not establish any of this.

### Named tests

| Pose | Suites | Result |
|---|---|---|
| Open, sideways | `DuoLayoutUITests`, `CoachPaneTests`, `DuoLayoutTests`, `CoachReplyLinesTests`, `CoachEngineTests`, `CoachReceiptPresentationTests` | 122 passed, 0 failed, 8 skipped (upright-only) |
| Closed | `DuoLayoutUITests` | 0 failed; the upright tests ran, including `testUprightTapStillPushesOverChat` (run at `e25fe2db`, before the spacing fix, which only touches the sideways pane) |
| iPhone 17, iOS 27.0 | `CoachNavigationUITests` | 5 of 5: 4 passed in the first run; `testTappingTheConversationClosesTheKeyboardAndKeepsTheDraft` timed out at 5 minutes on a cold simulator and passed on rerun (54 s) |

New tests, each seen failing first: `CoachPaneTests` (17),
`CoachEngineTests.progressAndDayReadsAreReported`, and in `DuoLayoutUITests`:
`testSidewaysChatSitsRightOfThePane`, `testSidewaysTapOpensMealBesideChat`,
`testSidewaysQuestionOffersProgressInPane`,
`testSidewaysWeightChangeMovesPaneToProgress`,
`testSidewaysChangeOnAnotherDayShowsThatDay`,
`testDeletingPaneMealReturnsToToday`, `testUprightTapStillPushesOverChat`.
`testSidewaysCoachShowsLiveDayAndHighlightsChange` now expects the live day on
the left.

### Already failing before this branch

On the closed Duo, `CoachNavigationUITests` fails three tests
(`testColdDiarySourceRouteBeforeCoachMountOpensExactSource`,
`testDiaryDayAndBackdatedMealUseSameCoachAndHonestNoChat`,
`testTappingTheConversationClosesTheKeyboardAndKeepsTheDraft`) with the same
messages at `55f40dcc`, which has none of the layout changes. They pass on the
iPhone 17. Not fixed here.

### By hand on the Duo simulator

Poses and rotation were driven through the device tool; XCUITest cannot fold or
rotate the inner display.

- Open, sideways: Today on the left, chat on the right, the chat clear of the
  system control strip. `coach-open-screen/sideways-today-beside-chat.png`
- Tapping a logged meal opens it on the left while the chat and its field stay
  usable. `coach-open-screen/sideways-meal-beside-chat.png`
- Book pose (130°): the two sides meet at the crease; the open meal survived
  the fold. `coach-open-screen/book-meal-beside-chat.png`
- On-screen keyboard with a draft and a meal open: the field stays above the
  keyboard. `coach-open-screen/sideways-keyboard-draft-and-meal.png`
- Rotated upright: the same meal is the normal pushed screen over the chat.
  Rotated back: it returns to the pane and the draft "keep this draft" is
  intact. `coach-open-screen/upright-meal-pushed.png`
- Table pose (half-open, upright): unchanged from `main`; a pushed meal covers
  the screen as before.
- CPU after the rotations and folds: 0.1% across three samples.

### Found and fixed during verification

- The first meal of a day opened that day's Diary view instead of staying on
  Today, because the diary has no active day yet when the receipt arrives. The
  landing rule now also compares the receipt's date with the turn's date.
  `firstMealOfTheDayLandsOnTodayBeforeTheDiaryCatchesUp` failed, then passed.
- The left pane kept a blank band for the system control strip, which is now
  on the chat's side. Fixed by ignoring the trailing inset inside the pane.
  This one has no automated test: list rows report their full width to
  XCUITest whatever the inset, and three attempts to measure a card failed to
  detect the band. The before and after were compared by screenshot.

### Independent review

One review of the whole branch against the design found two problems, both
fixed with a test that failed first:

- Switching profile could move the pane, because the other profile's latest
  turn looked like a new change. What the pane has seen is now kept per diary.
  `switchingProfileNeverJumps`, `skippedChangeNeverJumpsLater`.
- A meal open in the pane that Coach deletes, or whose creation is undone,
  left "Meal unavailable" there. The pane now returns to Today.
  `removalOfTheOpenRecordReturnsToToday`, `testUndoingPaneMealReturnsToToday`.

After the fixes, open and sideways: `CoachPaneTests` 20 passed and
`DuoLayoutUITests` 11 passed, 8 skipped (upright-only), 0 failed. The source
with these fixes is the commit after `39b520b8` on the branch.

Left as is: undoing a workout while its detail is open in the pane still shows
"Workout unavailable" (Coach deleting it does return to Today); and a pane
going from one meal straight to another reuses the same screen instance.

### Not verified

- VoiceOver: the "Showing …" announcement after an automatic move was not heard.
- Progress in the pane without Pip was not looked at on screen; the pane passes
  `showsCompanion: false` and the automatic move to Progress is tested.
- A change arriving while a sheet is open in the pane: covered by
  `openSheetSkipsTheJump` only, not exercised by hand.
- Profile switch with a record open in the pane: the fixtures have one profile.
- Accessibility text sizes sideways (falls back to one column on `main`).
- The by-hand session used on-device inference, not the scripted replies, so
  the meal values in the screenshots differ from the UI tests' fixture.
- No real device.


## Pull request 2: expand the chat

- App source: `3ea3c7e4` on `feat/duo-pane-expand`, stacked on pull request 1.
- Same environment as above.

The first version of this pull request expanded the side pane over the chat.
The owner tried it on a real iPhone Duo on 2026-11-15 and changed the decision:
Today already has its own tab, so the control should enlarge the chat. That
version is replaced, not kept.

How it works: a control in the chat's toolbar puts the side pane away and gives
the chat the whole sideways screen. The chat is then told it is not wide, so it
lays out as it does upright: one readable column, a tapped record pushed over
it, and "See today" offered again. Only a flat sideways screen can expand;
turning upright or folding ends it.

- Open, sideways: `DuoLayoutUITests`, `CoachPaneTests`, `DuoLayoutTests`,
  `CoachReceiptPresentationTests`: 58 passed, 0 failed, 8 skipped
  (upright-only). New test, seen failing first:
  `testSidewaysChatExpandsAndCollapses` (the pane leaves, the chat grows into
  the left half, the draft survives both ways, the pane returns on the left).
- By hand: `coach-open-screen/sideways-chat-expanded.png`
- Found afterwards: with the pane showing another day or a meal, expanding
  pushed that screen over the chat. Expanding now puts away whatever the pane
  held, and collapsing returns to Today.
  `testExpandedChatOpensAnotherDaysMealOverTheChat` failed, then passed
  together with `testSidewaysChatExpandsAndCollapses` (2 passed, run with pull
  request 3's code merged in). `testSidewaysTapOpensAnotherDaysMealBesideChat`
  is added coverage for a card on another day; it passed without a change.
- By hand, on a private copy of a real diary (removed afterwards): "Review /
  Edit" on a card from the day before opened the meal on the left side by
  side, and over the chat when expanded. The meal screen fills the whole width
  when it is pushed over an expanded chat; not capped.

Not reviewed independently: the earlier review covered the replaced version.
Not verified: that folding to book pose or turning upright while expanded
collapses it, the chat's scroll position across expanding, VoiceOver, and
anything on the simulator-only paths above. The owner's device has this build.
