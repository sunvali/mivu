# Mivu

Mivu is a native Swift iPhone meal diary in planning and early implementation.
The approved product design and execution plan describe the intended diary;
the current build is a diagnostic connection proof, not a working meal diary.

## Current status

The native diagnostic now includes callback handling, account identity and
protected sessions, model/Responses transport, and durable synthetic probe
recovery. On the iOS 27.0 iPhone 18 Pro simulator, the final aggregate run on
source commit `2f98f7c34741ef744b6fcdac9acc0ea9e0f39807` reported 117 passed,
0 failed, and 1 skipped across 118 declarations and 9 suites. The skipped test
is the opt-in browser smoke; its separate run passed 7/7. Independent review
approved the branch after its storage-state fixes, and the logout fix review
was accepted.

Owner consent and live provider behavior, physical-phone recovery, and full
VoiceOver/reduced-motion inspection remain unverified. This is not a working
meal diary or completed proof. No backup provider is selected.

The repository is private and its draft pull request is
[PR #1](https://github.com/yakov103/mivu/pull/1). No required CI runs have been
observed. Xcode 27's license was accepted by the owner; compilation and test
runs have since proceeded. The original license-blocked zero-test attempt is
retained as historical context in the [verification report](docs/verification/2026-10-11-native-connection-proof.md).

- [Product design](docs/superpowers/specs/2026-10-11-food-logger-design.md)
- [Approved implementation plan](docs/superpowers/plans/2026-10-11-native-connection-proof.md)
- [Current verification](docs/verification/2026-10-11-native-connection-proof.md)
- [Integration decision](docs/adr/0001-native-integration-decision.md)

## Development

Use Swift 6, SwiftUI, and platform APIs. Support English LTR, Hebrew RTL,
Dynamic Type, VoiceOver, reduced motion, and accessible touch targets. Use only
synthetic inputs in connection diagnostics. Never commit credentials, personal
meal data, or raw authorization responses. Use a feature branch and pull
request; record verification with its actual environment, command, result, and
remaining gates.
