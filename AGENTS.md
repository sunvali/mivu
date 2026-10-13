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
- Use Conventional Commit PR/squash titles. All hosted jobs use `ubuntu-slim`
  with two-minute limits for script and title checks only. No hosted macOS,
  self-hosted runner, native build/test, packaging or signing jobs are allowed.
- Run focused native checks locally with XcodeBuildMCP for Swift changes; record
  full native unit/UI verification locally for screen/navigation changes. Linux
  CI does not establish native acceptance. Record the exact tested source SHA.
- Version/changelog PRs and tags remain automated. Package and sign the exact
  version tag locally with Xcode/Organizer; record local evidence separately.
  Keep Actions usage/auto-packaging gates false and never count blocked or
  skipped native work as passing evidence.
- Local Git hooks are opt-in via `python3 scripts/ci/git_hooks.py install`.
  Preserve custom hooks. Commits check staged syntax/whitespace only; pushes run
  quick script checks and native units when native inputs changed or the baseline
  is unknown. Native pushes require the checked-out commit and clean native inputs.
- Reuse local native success only for identical inputs, recipe and environment;
  never cache failed, zero-test or malformed evidence. Hook units do not replace
  full local UI verification or independent Ponytail Review before merge.
