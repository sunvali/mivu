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

## Pull request 2: expand the pane

- App source: `499d271b` on `feat/duo-pane-expand`, stacked on pull request 1.
- Same environment as above.

How it works: the expand control shows a second copy of the pane over the whole
screen, laid out wide. The split, with the chat, stays mounted underneath at
its own size, so the chat's position and draft are untouched. The plan's
zero-width chat was not used, because resizing the chat's table risks its
scroll position.

- Open, sideways: `DuoLayoutUITests` and `CoachPaneTests`: 32 passed, 0 failed,
  8 skipped (upright-only). New test, seen failing first:
  `testSidewaysPaneExpandsAndCollapses` (draft kept, Today in two columns when
  expanded, pane back on the left after collapsing).
- By hand: expanded Today fills the screen in two columns and the collapse
  control sits in the system strip. `coach-open-screen/sideways-pane-expanded.png`

Independent review: no Critical or Important findings. Two small ones fixed:
only the copy beside the chat now decides automatic moves (two copies could
have written different results), and a profile switch collapses the pane even
while upright. Neither has its own test; the suite above ran after them.

Left as is: a meal opened by tapping a row inside the expanded Today is pushed
in the expanded copy only, so collapsing returns to Today beside the chat.

Not verified: book and table pose while expanded, rotation while expanded,
VoiceOver with the cover, a real device.

## Pull request 3: two-column Diary sideways

- App source: `94f83fa0` on `feat/duo-diary-columns`, stacked on pull request 2.
- Same environment as above.

Sideways, the Diary tab shows the week strip and the chosen day's summary on
the left and that day's meals and workouts on the right. Upright, and inside
the Coach side pane, it is the one list it was. `duoReadableWidth(evenWhenWide:)`
lost its parameter; Diary was its only user.

- Open, sideways, all three pull requests together: `DuoLayoutUITests`,
  `CoachPaneTests`, `DuoLayoutTests`, `CoachReplyLinesTests`, `CoachEngineTests`,
  `CoachReceiptPresentationTests`: 127 passed, 0 failed, 9 skipped (upright-only).
  New test, seen failing first: `testSidewaysDiarySplitsSummaryAndRecords`. It
  replaces `testSidewaysDiaryKeepsReadableWidth`. `testUprightDiaryStaysOneColumn`
  is new and was skipped in this pose; it has not run.
- iPhone 17, iOS 27.0, the six `DiaryUITests` that use this screen: 5 passed.
  `testLogMealFromSelectedHistoricalDayKeepsTodaySeparate` failed, and fails the
  same way at `a10f8a2c` before this change: run on a Sunday just after
  midnight, "yesterday" is in the previous week, so no pill reads "1 meal".
- By hand: `coach-open-screen/sideways-diary-two-columns.png`

Independent review: no Critical or Important findings. Noted, not changed: an
empty day leaves the right column blank; two tracking days on one date repeat
the "Meals" header on the right without a day marker; rotating recreates the
lists, so scroll position resets.

Not verified: the whole `DiaryUITests` suite on the open Duo fails 18 tests,
and that was not compared with `main` (the suite is run on a regular iPhone).
One full run on the iPhone 17 was cut off by a time limit at 18 of 23 with one
failure, the test named above. Book and table pose for Diary, the upright
one-column test, a real device.

## Half width beside another app: blocked

Not verified. The simulator tooling could not put two apps side by side: its
drag gesture has no speed control, and a drag from the home bar to the edge
went to the Home Screen. No change was made for this.

The nearest evidence is the closed pose, 466×678 points, against roughly
475×669 for half of the open screen: `DuoLayoutUITests` passes there. That is
not the same thing, because the system places its controls differently in a
split.

To try on a real Duo, with Mivu on each side of Safari in turn:

1. All four tabs show the phone layout with nothing clipped.
2. In Coach, type with the on-screen keyboard and send; the field stays visible.
3. Open the camera and the photo picker, and return.
4. Open a sheet and an alert; both stay inside Mivu's half.
5. Drag and tap "Jump to latest".
6. Resize to full screen and back; the draft and chat position survive.
7. The system controls sit on Mivu's outer edge and cover nothing.
