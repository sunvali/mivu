# Mivu

Mivu is a native iPhone food diary built with SwiftUI and Swift 6 for iOS 26 and
newer. Coach saves conversational text and photos, with Today, meal review,
History and Settings alongside it. The Hebrew language selector is disabled for now; existing profile
and archive data, including stored language values, must remain intact.

## Conversational tracking

Input saves locally before analysis. Connect ChatGPT and select an eligible model
in Settings to analyze meals; offline input remains available for retry. Food
operations update real diary records, and estimates remain open to review and
correction. Live text/image recognition still needs provider acceptance; the
[core verification record](docs/verification/2026-10-12-coach-core.md) distinguishes
tested native persistence from external and physical-device gates.

An explicit `--sample-mode` launch uses a clearly labeled synthetic apple estimate.
Sample mode and isolated inference fixtures do not establish food recognition.

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
for hosted checks and release prerequisites. For owner-run live testing after the core build is ready, see [personal iPhone testing](docs/development/personal-iphone-testing.md). The [accepted MVP addendum](docs/superpowers/specs/2026-10-12-sample-mvp-addendum.md)
records product and backup requirements.

## Development

Use synthetic inputs in diagnostics and tests. Never commit credentials or
personal meal data. Keep changes on a feature branch, preserve English LTR,
Dynamic Type, VoiceOver, reduced motion, and accessible touch targets. Hebrew RTL
is not an MVP acceptance requirement. Report verification with its actual
environment, result, and remaining gates; workflow files alone are not evidence
of a hosted run. The released baseline remains a sample diary; conversational food
tracking is implemented on this branch, while progress tracking and broader
coaching remain underway. See the [merged Coach foundation evidence](docs/verification/2026-10-12-coach-foundation.md), the [coach feature audit](docs/verification/2026-10-12-coach-feature-audit.md),
[conversational coach design](docs/superpowers/specs/2026-10-12-conversational-coach-design.md),
and [P0 implementation plan](docs/superpowers/plans/2026-10-12-coach-p0.md) for
the current scope and evidence.

## Agent guidance

See [repository instructions](AGENTS.md) and the concise
[Copilot instructions](.github/copilot-instructions.md).
