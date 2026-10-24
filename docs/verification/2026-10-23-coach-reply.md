# Coach replies — verification (2026-10-23)

Branch `feat/coach-friendly-replies`, based on `main` at `dd5e8c34`.
Spec: `docs/superpowers/specs/2026-10-23-coach-reply-design.md`.
Plan: `docs/superpowers/plans/2026-10-23-coach-reply.md`.

## Environment

- Xcode with XcodeBuildMCP; iOS 27.0 simulator `Mivu coach replies 2 (Claude)`
  (`7EBD9470-0C3A-46CC-BE34-D2094FC4EFA1`), checkout-specific DerivedData.
- Real-plan probes: `Mivu screenshots (Claude)` (`DD662DAB-…`), the owner's
  ChatGPT plan, synthetic questions only.

## Native results

| Run | Source | Result |
| --- | --- | --- |
| `MivuTests` (all unit tests) | `31f40ad0` + Task 7 test edits | 1138 passed, 0 failed, 1 skipped |
| Affected UI suites: `CoachUITests`, `CoachNavigationUITests`, `CoachCorrectionUITests`, `CoachHistoryUITests`, `CompanionUITests`, `CoachClarificationUITests`, `SmokeUITests` | pre-`0e03af05` (GeometryReader macro bar) | 48 passed, 3 failed |
| Rerun of the 3 failures | same | 2 passed (flaky timeouts), 1 failed: `testColdDiarySourceRouteBeforeCoachMountOpensExactSource` (app never idled) |
| `CoachNavigationUITests` + `testReceiptShowsCommittedDateAndUnknownEstimates` | `0e03af05` (Canvas macro bar) | 5 passed, 0 failed |

Known flaky, pre-existing: `CoachEngineTests.requestedProgressRereadsFactsAfterSuspendedInference`
fails intermittently on unmodified `main` `dd5e8c34` too.

Not re-run after `0e03af05`: the full unit target and the other affected UI
suites (the change only swaps how the macro bar is drawn).

## Real ChatGPT plan probes (build `79600d40`)

1. "How am I doing today?" — grounded 4-sentence prose instead of the 20-line
   fact dump; `**` shown raw (fixed later by inline Markdown).
2. Multi-dish dinner — one message with one receipt card. Prose repeated the
   dish list; names carried "(estimated …)"; odd units. Addressed by prompt
   rules and the Today-styled card.
3. "How many calories in a banana? Don't log it." — short answer, nothing
   logged. Its number passed only because it matched a diary value.
4. "Actually the fries were only half a portion" — correct edit; the app line
   was engineer-style. Replaced with "Updated Fries to 0.5 serving."

## Known limits

- General nutrition facts not in the diary or a lookup fail the number check
  and fall back to today's totals line.
- A wrong number that coincides with any number in context passes the check.
- Meal detail (Diary) still shows ISO dates.

## Real ChatGPT plan re-check (build `0e03af05`)

"Lunch: sushi set with miso soup, edamame and green tea" → one message: Pip's two
sentences ("Logged lunch at an estimated **740 kcal** … Today's recorded total is
about 3,300 kcal against your 1,600 kcal goal.") with no repeated dish list, and
a Today-styled card with plain dish names, per-dish calories, macro bar and
legend, and footer actions. Screenshot: `coach-reply/real-plan-sushi-lunch.png`.
