# Precision Glass implementation

Approved direction: 03 Precision, native Apple glass controls and opaque data surfaces.
Base: eddf0e5764346d835e2bc5381884b9b47945a736 (main).

## Delivered interface
1. Shared semantic palette, scalable typography, summary and ledger rows.
2. Four native tabs: Today, Diary, Progress, Coach; profile/settings sheet on each root.
3. Capture, meal review, corrections and evidence using existing store operations.
4. Diary, progress, goals, weight, workouts and settings hierarchy.
5. Calm Coach conversation and durable record receipts.
6. Vector app identity and reference documentation.
7. Native build, functional unit/UI regression, light/dark and accessibility visual review; independent review.

## Boundaries
No model/schema migration, new backend, health advice, new data providers, or changes to capture ownership, analytics eligibility, backup safeguards or inference lifecycle. Existing local data remains authoritative.

## Delegation
GPT-6.1 Sol: capture/detail; history/progress/settings. GPT-6 Luna: shared palette and components. Controller: shell, Today, Coach, integration and verification. All changes share this feature checkout with disjoint source ownership.

## Verification
Final native verification is recorded separately in `precision-glass-verification.md` after the implementation commit. Hosted Linux checks cover repository scripts only; they do not establish native acceptance.

## Journey completion
- First launch asks for a diary name or archive restore; existing local profiles reopen without migration.
- Capture returns a linked acknowledgement of local persistence. Nutrition status and backup acknowledgement remain separate.
- Historical capture, weight and workouts retain the selected day; weight corrections target the original record ID.
- Diary supports a native date filter. Progress exposes explicit eligibility, numeric chart alternatives and links back to the diary.
- Workout deletion, meal/photo deletion, dirty editors and dated goal changes require explicit intent.
- Settings preserves drafts on failure, returns to the originating tab, and keeps connection recovery reachable from waiting meals.

## Native adaptations and limits
- Settings is a native sheet with pushed sections so each root tab keeps its navigation state.
- Source detail shows the stored reference and item provenance. It does not invent structured source metadata or confidence.
- Photo labels identify the stored attachment and timing; the existing photo model has no authored description field.
- The icon includes default, dark and tinted 1024-pixel assets. A separately layered Icon Composer document is not included.
- Production authorization, physical camera/library permissions, Files-provider remote upload and physical-device acceptance require separate device checks.

## Stored history and move guards

Meal history displays the actual capture timestamp, current meal revision, saved
submission text, each submission’s base revision and state, and stored proposal
items/provenance when available. `MealSubmission` does not store per-change
timestamps, edit origin, or complete before/after snapshots. The interface names
this as saved submission history and does not invent a full audit trail or rollback.
No schema migration was introduced for historical data.

The Move meal sheet pins the original owner, meal revision, and waking day. A
selection is only a draft until Move is tapped; Cancel makes no record change.
The store checks the original revision and waking day inside the same owner-checked
transaction that moves the meal. A newer ingredient edit or another move therefore
rejects a stale sheet without changing that newer record. Moves preserve the meal’s
nutrition revision, so moving pending input does not mark its nutrition as saved.
A failed move keeps its destination selection and original stored meal for retry.
