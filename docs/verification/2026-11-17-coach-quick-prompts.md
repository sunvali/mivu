# Coach quick prompts

Plan: [2026-11-17-coach-quick-prompts.md](../superpowers/plans/2026-11-17-coach-quick-prompts.md).
Spec: [2026-11-17-coach-quick-prompts-design.md](../superpowers/specs/2026-11-17-coach-quick-prompts-design.md).
Branch `feat/coach-quick-prompts`.

## What changed

- One row of suggestion chips sits inside the Coach composer tray, above the
  message box, whenever the box is empty (keyboard up or down). Rules, not the
  model, choose them from the hour, today's meals, the goal, the weigh-in and
  what Coach just did.
- Questions ("How was yesterday?", "Calories left?", "Was it balanced?",
  "Protein ideas?", "Weekly trend?") send at once and carry an arrow disc.
  Diary changes ("Log lunch…", "Log weight…", "Smaller portion…",
  "Add a drink…") only fill the box.
- "Same lunch" (yesterday's meal in this slot) or "Usual lunch" (the most
  frequent one in 14 days) shows a thumbnail and kcal. Tapping it fills the
  foods and quotes the meal; Coach copies it exactly with the new `copy_meal`
  tool (fresh item IDs, same nutrition, needs `get_meal` and the revision).
- After a meal Coach saved, the chips follow up; an edited meal drops them.
- Hiding: a chevron collapses and restores the row (kept across launches),
  long-press "Hide this suggestion", and Settings → "Show suggestions".
- Pip keeps a short mood line beside the chips ("Dinner time?").
- Fit (owner ruling after the UX review): chip text is footnote size; two whole
  chips fit on an iPhone and the closed Duo; further chips peek and scroll,
  and a sliver peek stays hidden until scrolled in. The open Duo and short or
  very large-text windows show 2 chips. On the closed Duo the row steps aside
  while the check-in card asks for a weight.
- "Calories left?" needs a calorie goal; "Was it balanced?" (beside the live
  day, or without a goal) needs food logged today.
- "See today" and "See progress" under replies are gone; "See {date}" for a
  past day stays.
- All new strings have English and Hebrew in the catalog.

## Evidence

Source: `511f20ffe370ec73186445c468075b5a23ed238e` on `main` at `c84963f4`.
Later commits change docs only.
Environment: macOS 27.0.1, Xcode 27.2, XcodeBuildMCP, `-testPlan Mivu
-parallel-testing-enabled NO`. iPhone: "Mivu quick-prompts" simulator
(iPhone 17, iOS 27.0). Duo: "Mivu quick-prompts Duo" (iPhone Duo, iOS 27.1,
unfolded and sideways for the Duo tests).

| Run | Tests | Result |
|---|---|---|
| Focused, before the review fixes (`c84963f4` + branch) | `QuickPromptsTests`, `RecentMealsTests`, `CoachFindMealsTests`, `CoachCopyMealTests`, `CoachEngineTests/quotedRelogLogsTheSameKcal`, `CoachEditParityTests`, `CoachToolsFixtureTests`, `PipLineTests`, `CoachReplyLinesTests`, `CoachPaneTests` and 9 `CoachUITests` | 76 passed, 4 failed (all on the base, below) |
| Same set after the review fixes | as above, 8 quick-prompt `CoachUITests` | 77 passed, 3 failed (base) |
| Sliver-peek fix (`511f20ff`) | `QuickPromptsTests` and the 8 quick-prompt `CoachUITests` | 26 / 26 |
| Duo (`511f20ff`) | `DuoLayoutUITests`: `testQuickPromptsShowTwoChipsSidewaysAndSkipCaloriesBesideTheDay`, `testSidewaysCoachShowsLiveDayAndHighlightsChange`, `testSidewaysProgressQuestionAddsNoFollowUp`, `testSidewaysWeightChangeMovesPaneToProgress`, `testSidewaysChatSitsRightOfThePane` | 5 / 5 |

Quick-prompt UI tests: `testQuickPromptFillDoesNotSendAndTrailingSlotSwapsMicForSend`,
`testQuickPromptSendSendsTheQuestion`, `testQuickPromptsHideWhileTypingAndReturnWhenCleared`,
`testQuickPromptsStepAsideForAClarification`, `testHiddenSuggestionStaysHiddenAfterRelaunch`,
`testCollapseArrowHidesAndRestoresTheRow`, `testSuggestionsSwitchTurnsTheRowOff`,
`testRelogChipCopiesYesterdaysLunch`.

Failures that are not this change: each also fails on the base branch
(`6887c0e1`, PR #145's branch) in a separate checkout:
`CoachReplyLinesTests` `singleDayStatesIntakeTargetAndRoundedRemaining`,
`pastDayUsesItsDate`, `atMostTwoSentences` (the fact line reads "There's no food
recorded" for the test day) and
`CoachUITests/testFixtureMealCorrectionHistoricalReviewAndConversationRelaunch`
("Time unspecified" check, line 197 on the base). Seven `CoachEngineTests`
meal-time and progress-prose tests fail on the base too and were not part of
these runs.

`scripts/ci/languages.py check` passes.

## Design review

An independent reviewer specialised in AI-chat interfaces judged real simulator
screenshots (iPhone light, dark, Accessibility Extra Large; Duo closed with and
without the keyboard, Duo open): 68/100 in round 1 (labels cut off mid-word,
fade with nothing to scroll, unanswerable questions, collapse control read as a
chip, closed-Duo crowding with the check-in card). After the fixes and the
owner's fit ruling, round 2 scored 82/100 with no blocking findings; the
remaining sliver peek was fixed afterwards.

## Not covered

- Owner check on a physical iPhone and Duo.
- Hebrew right-to-left layout of the row, and VoiceOver on a device.
- The closed Duo with the keyboard up in the check-in card's weight field still
  lets the card touch the "Coach" title and the keyboard's Done button cover
  the mic. That is the existing card: `main` at `c84963f4` shows it worse (card
  cut off at the top, the old starter chips under History).
- The re-log fill reads the saved items as written ("Eggs 2 egg"); proper
  plurals need per-language rules.
- Android: not started (iOS first, by owner decision).
