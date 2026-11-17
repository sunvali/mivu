# Snap notification macros

Approved scope: add rounded protein, carbs and fat to the existing post-Snap meal notification, preserving calories, meal identity and review routing.

- [x] Locate the notification on current main and isolate changes from the older dirty checkout.
- [x] Add formatting tests before implementation: rounded macros, unknown values, partial totals, and proposal nutrition awaiting review.
- [x] Append a separate macro line to the existing body; preserve the calorie and review wording. Use native notification layout, with meal names confined to the title.
- [x] Run MealNotificationTests and directly affected CoachReplyNotificationTests through XcodeBuildMCP.
- [x] Verify representative text width at small-phone and accessibility sizes; distinguish text measurement from physical notification acceptance.
- [ ] Review the diff, record exact native evidence, and open a feature PR.

Keep unknown values as — and partial macro sums as ≥. Reuse the existing nutrition totals and localization catalog. No new dependencies or custom notification UI.
