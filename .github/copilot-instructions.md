# Copilot instructions

Follow the canonical [repository guidance](../AGENTS.md) and the linked Mivu
product plan, design system, and CI/delivery contract. Keep Swift changes small,
native, privacy-preserving, and accessible. The MVP UI is English-only; keep the
Hebrew selector disabled and preserve existing profile/archive data and stored
language values. Preserve sample mode, profile isolation, durable capture,
explicit backup acknowledgement, and deletion guards. Use synthetic data only.
Report named test and source evidence honestly. Do not infer hosted CI or release
success from workflow files. Never expose credentials or claim remote backup
sync from a local file-provider write.

Keep verification small: for a test-only edit, run only that test or suite. For
implementation changes, run the new/changed test and its direct callers' suites.
Use unit tests for UI state, formatting and validation; use suite selectors if
Swift Testing method selection runs zero tests. For UI/navigation changes add
`python3 scripts/ci/smoke.py --simulator-id <reserved-UUID>` (120-second cap), plus
a specific UI journey only when needed. Do not rerun unchanged passing checks,
or expand to all unit/UI tests after a focused pass. The default `MivuQuick`
plan runs just smoke. Reserve the full `Mivu` plan for releases, broad regressions
or an explicit request. This supersedes full-suite instructions in older plans.
Never use another agent's simulator; set `MIVU_TEST_SIMULATOR_ID` for push hooks.
