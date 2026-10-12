# Mivu

Mivu is a native iPhone food diary built with SwiftUI and Swift 6 for iOS 26 and
newer. The English-only MVP centers on Today, meal capture and review, history,
and settings. The Hebrew language selector is disabled for now; existing profile
and archive data, including stored language values, must remain intact.

## Sample mode

The diary works without a ChatGPT connection. Every meal uses the same clearly
labeled synthetic apple estimate; it is sample data, not food recognition.
Settings also offers an optional ChatGPT connection diagnostic, separate from
diary use.

## Private data and backups

Diary records are stored locally in separate app-owned profiles. You can choose
a private folder in Files for backup, or export and import a portable archive.
“Saved to backup folder” confirms the file-provider write; it does not confirm
that iCloud or another remote service has finished syncing it. Keep the folder
available and check the displayed backup status.

## Run on a simulator

Open `ios/Mivu.xcodeproj` in Xcode, select the `Mivu` scheme and an iOS 26 or
newer simulator, then run. Use XcodeBuildMCP for simulator builds, tests, and
interaction checks. See the [native MVP plan](docs/superpowers/plans/2026-10-12-native-diary-mvp.md)
for scope and acceptance, [design system](design-system/mivu/MASTER.md) for
visual and accessibility guidance, and [CI and delivery](docs/development/ci-cd.md)
for hosted checks and release prerequisites. The [accepted MVP addendum](docs/superpowers/specs/2026-10-12-sample-mvp-addendum.md)
records product and backup requirements.

## Development

Use synthetic inputs in diagnostics and tests. Never commit credentials or
personal meal data. Keep changes on a feature branch, preserve English LTR,
Dynamic Type, VoiceOver, reduced motion, and accessible touch targets. Hebrew RTL
is not an MVP acceptance requirement. Report verification with its actual
environment, result, and remaining gates; workflow files alone are not evidence
of a hosted run. The released baseline remains a sample diary; the coach
expansion is underway, not completed. See the [coach feature audit](docs/verification/2026-10-12-coach-feature-audit.md),
[conversational coach design](docs/superpowers/specs/2026-10-12-conversational-coach-design.md),
and [P0 implementation plan](docs/superpowers/plans/2026-10-12-coach-p0.md) for
the current scope and evidence.

## Agent guidance

See [repository instructions](AGENTS.md) and the concise
[Copilot instructions](.github/copilot-instructions.md).
