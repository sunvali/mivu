# Mivu contributor rules

Read the product design and approved plan linked in README before editing.
Use Ponytail: minimal complete, human-readable Swift; platform APIs first.
The linked taste-skill supplies applicable visual principles; follow Apple HIG
for this native app. No web frontend is required.

- Preserve unrelated changes; use feature branches and pull requests.
- Do not mention codex or ai in commit messages or pull requests.
- Use rtk for verbose shell output when available.
- Write the smallest meaningful failing test before behavioral implementation.
- Use XcodeBuildMCP for Apple builds, tests, and simulator operations.
- Report blocked checks honestly; never accept legal terms for the owner.
- Use only synthetic inputs in connection diagnostics and tests.
- Protect credentials in Keychain; never bundle secrets or log token responses.
- Do not substitute paid API access, enable billing, or publish publicly without
  the owner's explicit authorization.
- Keep analysis separate from meal calculations so a later server worker can
  consume the same small operation.
- Preserve durable local capture: save acknowledgement and backup-folder write
  acknowledgement are separate. Never claim remote sync from a file-provider
  write; retain pending errors and never restore stale data over deletions.
- The MVP UI and acceptance are English-only; disable the Hebrew language
  selector. Preserve existing profile/archive data and stored language values;
  do not require Hebrew RTL functionality for MVP acceptance. Keep Dynamic Type,
  VoiceOver, reduced motion, and minimum 44-point touch targets.
- For behavior changes, include focused evidence from source plus named tests;
  report the source revision, environment, result counts, and any blocked gates.
  A workflow definition is not evidence of a hosted run.
- Follow the PR/CI/release contract in [CI and delivery](docs/development/ci-cd.md):
  merge through a reviewed PR, verify required checks and artifacts, and keep
  release claims tied to the exact merged revision and observed run.
- Before merge, run Ponytail Review, fix blocking findings, and verify CI.
  Follow the owner's existing authorization for merging; do not add approval gates.
- Use Conventional Commit PR/squash titles. Run quick native checks on updates;
  record full native UI verification locally for screen/navigation changes.
  Hosted jobs use Slim for scripts and standard macOS for short unit checks;
  no hosted job exceeds eight minutes. Release packaging runs unit tests against
  the immutable version tag and remains explicitly requested by default. Do not
  count unit-only checks, cost-gated skips or blocked jobs as full UI verification.
