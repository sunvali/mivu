# Snap notification macros

Source: `0bba59c2af06a55a74d49fde54f5659af00adaee`.
Environment: local Xcode, iOS 26.5 simulator `C9C051B0-1AA2-4A8B-BA70-8C996FFAA35B`, checkout-specific DerivedData, XcodeBuildMCP.

- Before implementation: MealNotificationTests, 8 tests, 5 expected formatting failures.
- Implementation: MealNotificationTests + CoachReplyNotificationTests, 15 passed, zero failures.
- Final source: MealNotificationTests, 10 passed, zero failures. Includes 280-point macro-line measurement at default and largest accessibility sizes, partial and unknown values, and review-proposal nutrition.
- Final result bundle: `/Users/yaakovkhodorkovski/Library/Developer/XcodeBuildMCP/workspaces/mivu-snap-macros-0ee5b7e7265c/result-bundles/test_sim_2026-11-17T19-57-25-963Z_pid29387_79568178.xcresult`.
- String catalog validation and whitespace checks passed.
- Ponytail Review: inspected shared notification formatter, its CoachViewModel caller, totals helper, routing and tests; no blocking source findings. No data storage or routing changes.

Text measurement verifies the representative macro line fits at normal size and wraps within three lines at maximum accessibility size. Actual physical lock-screen/banner truncation remains unverified; iOS owns that layout. No physical notification acceptance claimed. One final test attempt encountered simulator Busy/preflight launch failure; retry passed.
