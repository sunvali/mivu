# Mivu diary upgrades: delivery roadmap

Status: proposed for owner review. This records the requested scope and delivery
order; it is not an implementation plan or evidence of completed features.
Baseline: `main` at `5a6342146d5e773f71a51b9e9da9eff35b5edb2f`.

## Product intent

Mivu is an AI-first food diary. Conversation is the primary way to capture,
understand and change records; manual controls remain a usable alternative.
The owner explicitly requires ongoing conversational add/edit access, including
after onboarding and after later manual changes. Preserve Precision Glass,
the original painted Pip, the four existing destinations, and private local
capture before remote analysis.

Success means less daily logging effort, correct recoverable records, useful
grounded explanations, and a companion that helps without delaying controls.
It does not mean maximizing the number of screens, prompts or animations.

## Contract across every delivery

- Native controls and Coach read and change the same owned records through
  shared validation and transaction operations. No second model-owned diary.
- A new editable record type ships with conversational reads, creation and
  editing in the same delivery. Omitted patch fields preserve saved values;
  explicit clearing is distinct from an unknown or absent answer.
- Delayed inference cannot overwrite a newer manual edit. Submitted payloads,
  operation identity, immutable receipts and replay protection remain intact.
- A receipt acknowledges durable local state. Animation or generated prose
  cannot establish persistence, remote backup sync or an unperformed action.
- Local capture and manual entry work without a provider. Deferred inference
  preserves input and resumes or retries with the original accepted identity.
- App code owns permission, account and Files handoffs. Coach can route to the
  actual native action and inspect its resulting state; it cannot invent success.
- Provider requests use explicit bounded data projections. Adding a field to a
  local profile must not automatically expand what ordinary inference receives.
- Every portable model addition includes validation, quota accounting, archive,
  backup and restore behavior. Preserve all existing profiles and history.
- English LTR, Dynamic Type, VoiceOver, Reduce Motion, Increase Contrast,
  Reduce Transparency and at least 44-point touch targets remain required.
- Use the existing SwiftUI/UIKit, SQLite, subscription-backed connection and
  Lottie stack. No new backend, billing, provider or product dependency is
  authorized by this roadmap.

## Independently reviewable deliveries

### 1. Reliable entries and shared editing

The [first scoped design](2026-10-19-reliable-entry-design.md) covers quantity
and unit semantics, device-derived timezone defaults, bounded reversible Diary
paging, and atomic offline numeric food entry with Coach/manual parity.
It leaves the unresolved keyboard frame warning as an evidence-led
investigation, not a speculative layout change.

### 2. Pip-led onboarding and ongoing personalization

Use a native one-question flow with conversational follow-ups. Pip welcomes,
listens and acknowledges actual progress; ChatGPT interprets consented answers
and proposes personalized goals. Support Back, permitted Skip actions, resumed
setup after relaunch, connection recovery, manual goals and goal-free tracking.
Existing profiles are offered setup without being reset or forced to replace
their goals. The first-meal step opens the existing Coach capture experience.

Persist typed bounded answers with the profile, not in transient view state or
UserDefaults. Native answer editing and `get_personalization` /
`update_personalization` tools use the same revision-checked operation. An answer
change invalidates pending proposals but does not silently replace active goals.

Question/proposal orchestration is separate from the current record-command
engine, reusing its connection transport. It exposes presentation output, not
unrestricted diary writes. Local policy owns required fields, eligibility and
numeric validation. The proposed activation rule is an editable preview followed
by **Use these goals**; this choice is subject to owner review. Accepting a
proposal and completing setup commit atomically, with replay protection and
checks against changed answers, accounts, models and dated goal revisions.

Before this delivery's implementation plan, its own design must pin the exact
questionnaire, estimation method, activity assumptions, bounds, exclusion rules
and explanation copy. These are product and health-policy decisions, not choices
to leave to a model or implementer. The NIH planner's adult-only scope and
pregnancy/breastfeeding exclusions are a relevant starting reference:
[NIDDK Body Weight Planner](https://www.niddk.nih.gov/health-information/weight-management/body-weight-planner).

Adding portable answers must also replace the current full-profile provider
serialization with an allowlist, and advance the portable archive envelope so
older readers reject rather than silently discard the new fields. Imported
consent history never grants provider-sharing authority on a new installation
or account. Setup weight does not create a historical weigh-in without a
separate explicit action.

### 3. Useful grounded conversation and weekly review

Keep existing bounded reads, revision checks, atomic writes and receipts.
Introduce a bounded answer-presentation contract for explanations and verified
observations using facts actually returned in the current turn. Invalid fact
references retain the deterministic fallback. Free prose is not permission to
invent quantities, comparisons, dates or successful mutations.

Progress and Coach share the same weekly analytics. Preserve missing/partial/
pending coverage, known sample counts and the separation of food and estimated
exercise burn. Test actual user questions as well as command execution, then
evaluate authenticated responses separately from native fixtures.

### 4. Fast repeated food and searchable history

Start with bounded recent committed foods and **Log again**. Repeat creates new
consumption with fresh record IDs and explicit date/portion, preserving the
selected source and uncertainty. Follow with favorites and saved meals/recipes,
including ingredient quantities, yield and serving basis. Template changes never
rewrite past consumption. Native and Coach share create/read/edit/delete and
consume operations for the same library records.

Add bounded profile-owned record and conversation search using stable existing
navigation targets. Coach gets the same search read operation. Omitted results
do not prove that a meal is unique, and result text remains untrusted data.
The library/search design must specify storage/index changes and interchange
before adding any new persistent schema.

### 5. Labels and barcodes

Add a reviewed label workflow with explicit per-serving versus per-100-g/ml
basis, shared nutrient provenance and quantity conversion. Label interpretation
is a proposal until accepted. Barcode scanning is a native handoff into the same
evidence/editor flow; the identifier itself is not nutritional evidence.

Select a barcode source only after checking coverage, permitted usage and rate
limits. The present USDA client deliberately excludes unproven branded gram
bases; do not remove that protection to simulate barcode coverage. Keep manual
label entry available and require no new personal API key for ordinary logging.

### 6. Platform access and companion finish

Health, widgets and Siri use the same owned, validated operations. Each needs a
separate integration design for authorization, duplicate prevention and edit/
deletion reconciliation. They do not introduce another nutrition store.

Pip improvements ship with the workflow they serve: reuse the existing rig for
onboarding, evaluate first-interaction loading, test interruptions and neutral
joins at actual phone size, and provide an app-level quiet preference editable
through Coach as well as Settings. Keep system motion/power/thermal policies.
Use physical-device recordings and profiling before claiming smoother playback
or lower energy use. A 60-fps asset setting is not a measured frame rate.

## UX improvements attached to their owning feature

- Onboarding explains local storage versus the data sent for analysis before
  requesting sharing, and demonstrates a real first capture.
- Coverage labels explain the next action, including **Finished logging today?**,
  while preserving complete, partial, unknown and untracked as distinct states.
- Limited-data reports offer a targeted recorded-day review action.
- Keep advanced provider diagnostics and optional nutrition keys out of the
  ordinary first-meal path.
- Reinforce honest recording and corrections without rewarding low intake or
  penalizing a day above its target.

## Parallel execution and evidence

The owner selected parallel subagents. Use separate agents for independent
owners after the corresponding written design and implementation plan are
approved. Shared diary/Coach interfaces are established first; dependent work
consumes those interfaces rather than inventing another path. Native builds,
tests and simulator interactions stay serial. Review and integrate each task,
then review the whole branch.

For each delivery, record exact source, environment, nonzero result counts and
remaining gates. Include paired manual/Coach journeys, retry without duplication,
stale edits, profile isolation, unknown values, archive round trips, offline use
and accessibility for the changed surface. Real authorization/model quality,
physical camera/VoiceOver/motion, Files remote sync and later platform
integrations remain separately evidenced acceptance work.
