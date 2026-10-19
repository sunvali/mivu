# Reliable food entry and shared editing

Status: proposed for owner review; implementation has not started.
Baseline: `main` at `5a6342146d5e773f71a51b9e9da9eff35b5edb2f`.
Parent scope: [diary upgrades roadmap](2026-10-19-diary-upgrades-roadmap.md).

## Outcome

Correct quantities without corrupting nutrients, start new diaries in the
device's timezone, browse older days without losing a route back, and enter a
new food's known nutrition without a network connection. Coach must be able to
read and edit every resulting record through the same shared rules.

The owner approved an AI-first app with manual alternatives. This delivery
adds a secondary manual nutrition action without replacing conversational
capture or creating a parallel diary. It preserves existing accepted capture,
ownership, revision and receipt contracts.

## Existing owners

- `DiaryDatabaseMealMutations.swift`: shared ingredient correction, atomic meal
  mutation and bounded day-history queries.
- `DiaryModels.swift`: portable food, meal, submission and profile types and
  validation.
- `DiaryStore.swift` and `DiaryViewModel.swift`: owned operations, projections,
  refresh and durable-save feedback.
- `CoachManualEdits.swift`, `CoachTools.swift`, `CoachWriteFingerprint.swift`
  and `DiaryDatabaseCoachMutations.swift`: patch intent, parsing, fingerprinting,
  atomic conversational writes and replay.
- `MealComposerView.swift`, `MealDetailView.swift`, `TodayView.swift` and
  `HistoryView.swift`: native capture/edit entry points and history presentation.
- `DiaryArchive.swift` and `FolderBackup.swift`: portable interchange and backup
  acknowledgement. No full-snapshot reconstruction enters ordinary UI paths.

## Quantity, units and explicit nutrient intent

Every ingredient edit carries the explicit nutrient keys supplied by the user
or tool. Supported keys are exactly `kcal`, `protein`, `carbs`, `fat`; reject
other keys at the boundary. A supplied value equal to the old value still means
an explicit total, and supplied null means unknown. The native editor tracks
which nutrient fields were edited; Coach uses the keys actually in its patch.
Quantity-only corrections supply no explicit nutrient keys.

For the same unit, scale untouched known nutrients by new quantity / old
quantity, using the existing per-unit basis when needed. Overlay explicit
nutrient totals afterward. Preserve unknown values. Explicitly changed totals
use user provenance; scaling retains the original source and uncertainty.
Compute the new nutrition basis from the final values. A zero quantity retains
the valid same-unit basis so a later positive quantity can be restored.

Provide a small fixed conversion table for mass (`mg`, `g`, `kg`) and volume
(`ml`, `l`). Accept case-insensitive `milligram(s)`, `gram(s)`, `kilogram(s)`,
`milliliter(s)`, `millilitre(s)`, `liter(s)` and `litre(s)` as their matching
abbreviations; trim surrounding whitespace. Equivalent known units use the physical
quantity ratio before applying explicit totals. No density-based conversion
between mass and volume, and no inferred conversion between a count/serving and
mass/volume. Arbitrary existing unit labels remain supported unchanged.

For an incompatible/unknown unit change, require every previously known
nutrient to be explicitly supplied or explicitly cleared. Otherwise reject the
edit with an actionable amount/unit message, retaining the draft and saved
record. Clear the old unit's basis, including at zero quantity. Never silently
reuse a gram basis for a new serving unit. Native and conversational errors
expose the same rule; no mutation occurs on failure.

Examples that define the behavior:

| Before | Requested edit | Result |
| --- | --- | --- |
| 2 pieces, 160 kcal, 20 g protein | Quantity 4; no nutrient fields | 320 kcal, 40 g protein |
| 2 pieces, 160 kcal, 20 g protein | Quantity 4; explicit kcal 160 | 160 kcal, 40 g protein |
| 100 g, 200 kcal | 1 kg; no nutrient fields | 2,000 kcal |
| 100 g, 200 kcal | 0.1 kg; no nutrient fields | 200 kcal |
| 1 serving, 200 kcal, unknown macros | 150 g; no nutrient fields | Reject; retain original |
| 1 serving, 200 kcal, unknown macros | 150 g; explicit kcal 240 | 240 kcal; macros remain unknown |
| Positive amount with valid basis | Zero, then positive in same unit | Restore from that basis |
| Zero g with stored basis | Change to serving without explicit known totals | Reject; never reuse the gram basis |

Keep previously accepted operation fingerprints and receipts valid. New direct
edit fingerprints include explicit nutrient intent, including equal-valued and
null fields. Do not change immutable historical receipts to match later edits.

## New-profile timezone

Resolve `TimeZone.current.identifier` once when creating a new profile. Existing
saved profiles, archives, accepted request clocks and historical day labels
retain their stored timezone. Moving or travelling does not silently reassign
records. The native timezone editor and Coach's explicit preference patch
remain available. Synthetic tests that require a particular timezone set it
explicitly instead of relying on the device's environment.

## Atomic offline manual entry

Add **Enter nutrition manually** as a secondary action from the existing
capture experience and from a selected recorded day. Reuse it for **Add food
manually** on a saved meal, with that meal's expected revision. The native form
creates one food entry: required name, positive quantity defaulting to 1, unit defaulting
to serving, and optional calories/protein/carbs/fat. At least one nutrient must
be supplied; zero is a supplied value and blank is unknown. Use the same shared
item bounds for native and Coach operations: finite quantity at most 100,000
(zero remains permitted for existing-item corrections), each known nutrient
finite and in 0...10,000,000, name at most 500 characters and unit at most 100
characters. Reuse `validateItems` and remove conflicting smaller UI-only caps
where necessary; do not add a nutrition-estimation policy to manual input.
This is recorded user input, not an assertion that nutrition has been verified.

Date selection uses the existing waking-day decision. Explicit historical-day
entry is date-only and does not activate that day or change Today. No connection,
lookup key or model response is required. This first manual form does not add a
second photo pipeline; photos/notes can use the existing meal actions afterward.

Allocate meal, submission and item identities once in the draft (append retains
the existing meal ID). Freeze the
accepted payload, target day, clock and precision at the first save attempt.
One owned SQLite transaction validates input and commits the saved meal, items,
submission evidence and state, including starting a new current day when the
accepted day decision requires it. A failed commit must not leave an invented
empty day. An append preserves all existing ingredients and refuses stale or
unresolved meal state. Success returns the actual persisted projection.
Do not implement this as capture followed by a separate analysis commit.

Persist bounded original acceptance metadata and a canonical accepted-payload
fingerprint on the original manual submission. Metadata retains operation kind,
original day/date/timezone, clock/precision, expected target revision for append,
and the IDs of the entered items. Reuse the immutable original submission
proposal for those item values instead of duplicating photo/food payloads.
This makes the fingerprint verifiable even after a meal is moved or edited.
Identical retries identify the same saved meal and original accepted
submission, alongside the current projection. A changed payload
with that identity fails without mutation. A deleted accepted meal cannot be
resurrected by a retry. Failed persistence retains the draft and emits no save
reaction. Later edits do not change the original accepted payload or cause the
retry to reapply it; distinguish original acceptance from the current edited
projection. No fake conversation turn is created solely to supply a receipt.

Reuse the existing meal-item transaction operations inside both this native
entry and Coach's food writes. A manual meal is immediately discoverable through
bounded context/meal reads, editable with `get_meal` + `edit_item` / `correct_item`,
and appendable through the existing `append_food` path. Directly entered native
values use user provenance. Existing conversational estimates retain estimate
provenance; explicit `edit_item` nutrient corrections use user provenance.
Equivalent record access does not mean pretending that a generated estimate is
a confirmed label. Dedicated label evidence is a later delivery.

The native form reads current manual and Coach edits from the same record.
Stale revisions fail without overwriting newer data. Existing `CoachReceipt`,
command fingerprints and replay-only recovery remain the conversational write
contract. Save feedback, totals and source labels follow the shared committed
result. This feature does not mark a whole day complete automatically.

## Reversible bounded Diary history

Keep one resident page of at most 30 day summaries. Track only previous
page-start cursors so **Newer days** and **Latest days** return toward recent
records; do not accumulate all historical day models. Only one page request is
accepted at a time. Tag each request with selection, filter, change generation
and request identity; obsolete results cannot replace current rows.

Reset cursor navigation when profile/timeline identity, filter or relevant data
generation changes. Preserve the chosen date filter across ordinary navigation.
An exhausted edge performs no additional query. Retain explicit loading/retry
state and previous visible data on failure. Preserve native scrolling and focus;
the Coach timeline's distinct 100-exchange capacity contract is unchanged.

## Interchange and lifecycle

The optional manual submission acceptance is backward-decodable when absent;
validate new fingerprints and their original payload association on import.
Write portable archive envelope version 4 and keep reading versions 1 through 3
as legacy submissions without verified manual acceptance. Older readers must
reject version 4 rather than silently stripping replay evidence. A legacy
submission cannot authorize a new verified-manual retry by matching its ID
alone; reject an unverifiable collision without mutation.
This delivery introduces no new table and does not advance the physical SQLite
version merely for an optional JSON field. Archive/export/restore and quota
checks must round-trip new manual entries and retain replay protection.

Profile switching, sign-out, restoration, cancellation and low disk/quota
failure must preserve the current ownership and transaction rules. Never put
accepted food records or mutable source truth in UserDefaults or view state.

## Verification required

- Shared correction tests cover every numeric example above, mixed explicit
  and implicit nutrients, null/equal-valued patches, unknowns, incompatible
  conversions, zero basis behavior, invalid inputs and stale revisions.
- Run those rules through native editor submission and Coach parsing/writes,
  including directly constructed write fingerprints and replayed old receipts.
- New-profile tests inject/pin two device timezones and prove old profiles,
  archives and historical day labels are preserved.
- Manual-entry and append tests prove atomic failure/rollback (including new-day
  creation), identical retry, mismatched
  retry, deletion before retry, relaunch, preservation of unrelated ingredients,
  unresolved/stale append rejection and profile isolation.
- Paired native/Coach journeys create a manual entry, edit it conversationally,
  edit it manually, then reject a delayed stale correction. Both show the same
  quantities, totals, uncertainty and source labels after relaunch.
- Archive round trips retain manual evidence and replay behavior; legacy
  submissions without the new field remain readable.
- History tests cover more than 60 days, earlier/newer/latest navigation,
  overlapping requests, filter/profile changes, failure/retry and exhausted edges
  while keeping the resident page bounded.
- Native UI checks cover offline/manual creation from Today and a historical
  day, invalid input with draft retention, keyboard behavior, light/dark,
  largest Dynamic Type, VoiceOver labels and 44-point targets.
- Preserve the captured keyboard frame-warning scenario. Locate its native
  origin before attributing it to a view or changing layout. An app-owned cause
  gets a focused regression; a system-only warning is recorded as such.

Use XcodeBuildMCP for serial local native verification; record exact source,
nonzero counts and result bundles. Screen/navigation changes require the
repository's full local unit/UI acceptance, not only script CI. Provider and
physical-device checks remain distinct from injected native fixtures.

## Scope boundary and execution

This delivery does not implement personalized goal recommendations, library/
recipe storage, search, barcode sources, platform integrations or new Pip art.
Those requested features remain in the parent roadmap and receive their own
scoped designs. No third-party dependency, provider or billing change is needed.

After owner approval of this written design, create its implementation plan.
The owner has already selected parallel subagents: isolate correction semantics,
timezone, paging and manual-entry owners where independent; serialize shared
interface integration, native builds/tests and final review. Do not rerun long
unchanged baseline suites solely for this documentation commit.
