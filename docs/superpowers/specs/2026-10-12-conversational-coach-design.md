# Conversational nutrition and fitness coach

Owner direction: expand the existing Mivu app after inspecting its current code,
recording a feature matrix and planning P0–P3. This supersedes the earlier
apple-only assumption for product development; deterministic samples remain
test fixtures. Execute incrementally using the already requested parallel Sol
feature workers and Luna documentation work. English and native iPhone remain
the product focus. Diabetes- and celiac-specific functionality are excluded.

## Outcome and existing foundations

Mivu becomes a conversational coach backed by its own durable records. Food,
weight, workouts, targets and conversations have explicit owners, stable IDs,
timestamps, tracking days and provenance. Responses read saved data and cannot
substitute plausible numbers for missing history. Photos and text are captured
quickly; inference can continue after capture. A failed write never produces a
successful-save message.

The [feature audit](../../verification/2026-10-12-coach-feature-audit.md) is the
baseline. Reuse `DiaryStore`, its Codable values, day assignment, nullable totals,
review/correction/revision guards, photo preparation, Keychain/OAuth, streamed
Responses client, native views and versioned private archive. Current diary
analysis is a sample; the separate provider diagnostic is not live meal logging.

## Architecture decision

Keep Foundation business values and the `DiaryStore` actor as the authority.
Replace its private JSON persistence with one native SQLite database per profile;
use transactions, foreign keys, indexed day/history records and separate photo
BLOBs. Existing callers keep their actor API. A native SQLite change behind that
boundary is smaller than converting the entire graph to SwiftData objects or
adding a remote backend. No new app, generic repository framework, paid service,
or parallel source of truth is introduced.

Migrate a validated legacy JSON profile into a temporary database in one
transaction. Read it back and require value equality before atomically selecting
the database. Migration failure leaves the original usable. Once the database is
authoritative, never silently fall back to a stale JSON copy. Detect replaced,
missing or corrupt database files and competing stale writers before acknowledging
a save. Keep the existing portable archive rather than exporting database files.
New persistent entities must extend the archive compatibly; accept v1 imports and
test deletion/lineage protection through each format change.

## Live inference and local operations

Reuse the documented direct ChatGPT-plan OAuth route for the local app. A single
selected-account session supplies model choices, token refresh and authenticated
requests to both the diagnostic and coach. Credentials remain in Keychain and
outside archives. Eligibility, browser consent, callback completion and quota
are real human/provider gates; fixtures do not prove them. No paid fallback is
automatic, and remotely hosted or paid distribution requires a separate provider
decision.

The [current preview contract](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
requires streamed requests with `store: false`, explicit request history and
supported fields. Use developer instructions and a small `mivu` function
namespace. Do not depend on hosted conversation storage, file search, MCP,
computer use or tool search. The existing client must support validated JPEG and
PNG input, tool-only completed responses and multiple function calls. A stream
is not successful until its terminal completion event.

Persist the user's turn and attachments first. Local operations validate arguments
and bind the selected profile in code; the model cannot choose another owner.
Read tools return bounded actual records and current revisions. Write tools use
stable operation IDs, stored receipts and guarded transactions. A retry returns
the existing receipt instead of writing again. Unknown IDs, stale revisions,
deleted records and invalid numbers fail closed. Return committed results to the
model and render authoritative totals/receipts from those records. If persistence
fails, show the failure and retain the input instead of displaying a model's save
claim.

Keep meal proposals separate from conversation prose. Multi-food logging writes
one meal with individual item IDs. A correction such as “half the bread” selects
that stored item and updates its quantity/basis; other items keep their values and
sources. Additions and leftovers use the same guarded operation paths. No negative
compensation entry or duplicate meal is created. Conversation references persist
across launches and resolve against real saved IDs.

## Food evidence and days

Prefer retrieved nutrition records, confirmed label values and explicit user
corrections to model guesses. Record the source, serving basis and uncertainty.
A model cannot promote its own estimate to verified provenance. Photos estimate
portions rather than proving exact quantities. Label and restaurant lookups must
retain uncertainty when their sources cannot be retrieved or matched. Food
categories use the same item model, including beverages, snacks, desserts and
alcohol; alcohol calories need not equal the three macro energy sums.

Retrospective input uses the profile's local date and a stable historical tracking
day. If a time is unspecified, preserve that precision instead of claiming an
invented exact time. Keep the existing waking-day/midnight ambiguity rule and
explicit morning-day signal. Add explicit close-day state: untracked or partial
days remain distinct from known zero intake. Pending captures or unknown nutrients
prevent a complete numeric consumption claim. Adding or correcting records
recomputes affected summaries directly from records, including closed days.

## Native experience

Add Coach as the first native tab. Keep Today, History and Settings as useful
existing surfaces. Coach has durable user/assistant turns, a compact current-day
summary, text/photo/camera input, clear pending/retry states and easy record links.
Reuse photo preparation and existing meal review/edit screens. Correct source
labels must replace sample-only wording before displaying real results. Preserve
cream/coral/apricot/sage styling, system glass, SF typography, native navigation,
44-point targets, Dynamic Type, reduced motion/transparency and semantic labels.
Charts have accessible text equivalents. Do not build a second capture system or
turn the app into a spreadsheet form.

## Milestones and exit criteria

| Milestone | Complete connected deliverable | Required evidence |
|---|---|---|
| P0 core tracking | Transactional native storage; live text/photo multi-food logging; evidence/provenance; selective and historical corrections; close-day semantics; a durable Coach route using actual totals. | Legacy migration/rollback, owner/revision/retry tests; real native persisted-food journeys; live provider text/image proof distinguished from fixtures. |
| P1 progress | Explicit dated calorie/macro/weight goals; remaining budgets; conversational weights/workouts; exercise energy separate from food; Swift Charts and daily/weekly/monthly missing-aware analytics. | Unit/date-range/rolling-average/unknown-coverage tests; native goals/weight/workout/report workflows and archive roundtrips. |
| P2 intelligent coaching | Bounded historical retrieval and persistent preferences/references; meal/protein recommendations, realistic fitness-challenge suggestions, progress and weekly reviews, sufficient-data plateau explanations and explicit goal proposals. | Exact owner scenarios after relaunch; tool receipts and actual history; realistic challenges matched to activity/preferences; sparse/conflicting history, unavailable data and harmful compensation requests handled correctly. |
| P3 advanced | Habits/challenges, supplement tracking, configured reminders, planning/favorites/reusable meals, optional fitness imports and complete data portability. | No inferred consumption from plans; imported activity deduplication; permission/deletion/export/restore tests and real provider gates. |

Targets are explicit user settings, not guessed prescriptions. Intake averages
show their coverage and exclude untracked/missing days. Weight trends use actual
measurements, normalize units and show rolling-window sample counts; no absent
measurement is filled with zero. Plateaus need adequate trend and tracking data
and remain an observation rather than a diagnosis. Any exercise-adjusted budget
is an explicit preference, with consumed food and estimated burn shown separately.

Coaching supports realistic, sustainable habits and ordinary recovery after
setbacks, following [general CDC guidance](https://www.cdc.gov/healthy-weight-growth/losing-weight/index.html).
It must not recommend crash dieting, extreme restriction or punitive exercise,
interpret a short-term scale change as fat gain, automatically lower a target,
or invent history. Supplement tracking does not imply dose prescribing.

## Verification and delivery

Each slice has a meaningful failing test, native/fixture distinction, independent
Ponytail Review and exact source-bound evidence. Run targeted checks first, then
the relevant aggregate once after integration. Use XcodeBuildMCP locally and the
existing Actions workflows for hosted checks and immutable release products.
Merge through a reviewed PR under the owner's existing authorization. Source
inspection, fixtures, simulator testing, hosted CI, live provider testing and
physical-device acceptance are reported separately. Preserve the existing
unverified Files-provider journey as a visible gate; do not call a folder write
remote cloud sync or claim Apple signing without credentials.
