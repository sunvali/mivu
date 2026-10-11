# Mivu

A native Swift iPhone meal diary. Capture a photo, write a note, or both; send
and continue your meal while analysis runs. Corrections update the same meal.
Photos stay attached until you delete them.

## Current work

A minimal native scaffold and the first state test are prepared on the feature
branch. The generated screen is still Hello World; connection behavior has not
been implemented. The first planned slice is a diagnostic connection proof for official authorization
with the user's own ChatGPT plan. It must establish native iPhone compatibility
before the diary, private backup, or optional Siri work proceeds.

- [Product design](docs/superpowers/specs/2026-10-11-food-logger-design.md)
- [Approved implementation plan](docs/superpowers/plans/2026-10-11-native-connection-proof.md)

This repository is private. No public release or completed application is claimed.
Xcode 27 is installed locally, but its license needs owner review and acceptance
before builds or tests can run.

## Development

Use Swift 6, SwiftUI, platform APIs, and the smallest readable implementation.
Support English, Hebrew RTL, Dynamic Type, VoiceOver, and reduced motion.
Never commit credentials, personal meal data, or raw authorization responses.
Use a feature branch and a pull request. Verification instructions are in the plan.
