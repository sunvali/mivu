# Mivu: private iPhone MVP

Date: 2026-10-11, Asia/Jerusalem. Status: accepted for implementation planning
when the owner requested implementation on 2026-10-11. The written execution
plan was approved for native execution with independent review on 2026-10-11.
Remaining infrastructure choices and public release are not approved.
This is a separate product and design workspace, outside Shutfush.

## Product brief and decision record

Build a food diary that the owner can use throughout the day with less effort
and more dependable records than the current conversational workflow. A
possible developer collaborator has a separate private account. Public release
is a later goal. The referenced private ChatGPT project could not be retrieved;
this spec uses the supplied workflow summary and interview answers.

Confirmed decisions:

- iPhone first. Connecting ChatGPT and everyday use must work without a computer.
- Use native Swift for the iPhone application. Investigate iOS 27 Siri AI beta
  integration; this request does not yet make beta Siri a required MVP dependency.
- Host the product's source repository on GitHub, separately from Shutfush.
  `yakov103/mivu` was created privately at the owner's request. Source
  hosting does not select the app's backup or analysis runtime infrastructure.
- Analysis uses each user's own ChatGPT plan through official authorization.
  Publishing the source is acceptable if eligibility requires it; it does not
  establish native compatibility or approve a public service launch.
- Today is the opening screen, with a prominent Log meal action.
- Capture a photo, upload photos, write text, or combine them, then Send and eat.
  Default logging saves after successful analysis. Review-first is also available.
- Capture works offline. Analysis attempts background completion and safely
  resumes when the app can run again if interrupted.
- Unclear portions receive visibly uncertain estimates in quick logging.
- Correct through a message/photo or direct item editing, updating the same meal.
- Add before/after photos and extra details from the existing meal.
- Photos remain attached until explicitly deleted.
- Use waking-cycle tracking days. Start new day and morning weight are visible
  actions; weight is optional. Ask once when day assignment is ambiguous.
- Finish day optionally records completeness for summaries, independently of
  starting a new day.
- Signing in on a replacement phone restores private records and photos that
  have successfully backed up.
- UI switches between Hebrew RTL and English LTR; input accepts both languages.
- Prefer free infrastructure. Up to USD 10/month may be justified by the design;
  this is a planning ceiling, not permission to create paid resources.
- Keep a small analysis boundary that permits a later server worker.
- Apply the ponytail skill throughout implementation: minimal complete code,
  human-readable Swift, and current Swift platform practices.
- Use the owner's linked taste-skill for applicable frontend design guidance,
  adapted to the approved native iPhone platform.
- Nutrition-quality scoring and target-progress bars are deferred.

Success: during a 14-day pilot, ordinary logging needs only capture and Send,
corrections require no manual reconciliation of totals, and the owner prefers
this workflow to the existing one. Acceptance tests must show no duplicate
meals from retries or corrections. These are proposed acceptance criteria,
not observed outcomes.

## MVP and exclusions

Include meal capture, analysis, optional review, direct editing, corrections,
attached photos, calorie/carbohydrate/protein/fat estimates, daily totals,
earlier-day browsing, day completeness, optional weight entries, basic dietary
preferences, private backup/restore, export/deletion, and connection settings.
Basic intake totals remain part of the approved flow; nutrition scoring is extra.

Defer nutrition scores, goal-setting recommendations, exercise, weight-trend
charts, social sharing, payments, public signup, Android, a web diary, barcode
scanning, push notifications, automatic grouping of unrelated submissions,
and a server analysis worker. No spreadsheets are required for storage or use.

## Screens and flow

**Today:** tracking-day label, Start new day, Log morning weight, recorded totals,
pending count, recent meals, and Log meal. Show empty days as having no recorded
meals and unknown completeness. Pending analysis does not count as zero intake.

**Log meal:** one composer accepts camera/library photos and optional text. At
least one photo or nonblank text is required. Quick log is the default; Review
first is a visible per-submission choice. Send persists the payload and stable
meal/submission IDs before acknowledging capture, then returns to Today. Capture
does not wait for inference. If local persistence fails, stay in the composer
and preserve the input rather than reporting Sent.

**Meal:** photos, food items, consumed quantities, nutrition, provenance,
uncertainty, and current processing state. Add photo or details targets this
meal explicitly. Message corrections and direct edits use the same revision
and totals logic. After photos describe consumption within this meal; they do
not create a second meal. Quick logging offers undo by deleting that submission
or meal; an in-flight result must not resurrect an undone entry.

**History/day summary:** select earlier dates and inspect their meals, recorded
totals, completeness, and optional weight. Finish day sets Complete, Partial,
or Untracked. Unmarked days remain Unknown. Distinguish recorded totals on a
partial day from complete-day intake. Report coverage counts in summaries;
aggregate complete-day intake separately from partial records. An explicitly
confirmed empty complete day may have zero intake; absence of logs alone cannot.

**Settings:** language, timezone, dietary preferences/restrictions, account,
ChatGPT connection and usage link, backup status, export, and deletion. A food
photo cannot establish gluten-free status or compliance with a restriction.

All screens support Dynamic Type, VoiceOver labels, reduced motion, RTL,
and accessible touch targets. Visual styling is not finalized by this spec.

## States and background behavior

Submission states: Captured, Waiting for connection, Analyzing, Awaiting review,
Saved, and Needs retry. A correction can be pending while the last saved revision
continues contributing to totals. Malformed or interrupted output never replaces
the saved revision or contributes a partial total. Review-first output counts
only after Save. Canceling or deleting makes late responses inapplicable.

Connection states: Disconnected, Connected with plan usage authorized,
Signed in without plan permission, Unavailable, and Quota reached. Connected
does not claim successful inference. Demonstration mode is separately labeled
and never mixes simulated results into the live diary.

Try background completion after Send. If iOS interrupts the worker, retain the
job and resume when execution is allowed or the user returns. Reconnection alone
does not guarantee execution while the app is suspended. Transient network errors
use bounded backoff; quota, ineligibility, and revoked authorization pause jobs
for user action. A lost stream can require another inference request and consume
additional plan usage, but committing its result cannot duplicate the meal.

## Tracking-day rules

Store the eaten timestamp separately from the selected tracking day. A 04:00
burger can belong to the preceding waking day. Explicit Start new day opens
the new day; Log morning weight can use that same transition before recording
the measurement. A repeated tap or weigh-in reuses an already-open new day.
The date label is the local date when the waking day began.

Do not infer sleep from the type of food. The analyzer may suggest assignment,
but an ambiguous assignment is resolved by Previous day / New day. Missing
weight never gates logging or changing days. Historical meals can be moved to
another day, updating both days' totals.

Proposed fallback for written review: a Previous day answer is valid for four
hours or until another local calendar-date change, whichever comes first. If
the active day is still from an earlier local date after that confirmation
expires, ask again on the next submission. This avoids carrying an old day
forward indefinitely when the user forgets both morning actions. There is no
automatic nutrition-based day selection or silent clock cutoff.

Default timezone is Asia/Jerusalem; timezone is configurable. Preserve UTC
timestamps plus the tracking day's timezone and date label. Travel or a timezone
change must not silently reassign historical meals. Ask about the active day
when the timezone change makes assignment ambiguous. Weight measurements and
food completeness remain independent.

## Data model and calculations

| Record | Required information |
| --- | --- |
| Profile | App-owned user ID, UI language, timezone, nullable dietary preferences/restrictions |
| Tracking day | ID, owner, local date label, timezone, start timestamp, completeness |
| Meal | ID, owner, tracking-day ID, eaten/captured timestamps, current revision, review mode |
| Food item | ID, meal ID, name, consumed quantity/unit, nutrition values, provenance, uncertainty |
| Photo | ID, meal ID, private stored object, capture/import timestamp, optional before/after role |
| Submission | ID, owner, meal ID, initial/correction intent, base revision, text/photo references, state |
| Correction | Meal ID, revision, timestamp, message or edited fields; sufficient history to explain the change |
| Weight | ID, owner, measurement timestamp, value/unit, optional tracking-day association |
| Connection | Verified provider identity, issued client ID, granted scopes, expiry, credential-storage reference |

Calories use kcal; macros use grams. Unknown values remain nullable. Each value
records whether it is a confirmed package-label value, another identified
source, user-supplied information, or a model estimate. Label extraction that
has not been checked stays unconfirmed. Preserve the reference and basis, such
as nutrition per 100 g, when scaling to the consumed amount. Confirmed source
values take precedence over generic estimates for that item.

Meal totals are the sum of the current saved food items; day totals sum saved
meals assigned to that day. Calculate from stored numeric quantities, not from
the analyzer's prose or an independently returned day total. Round for display
after summing. Disclose unknown components rather than treating them as zero.
Direct edits update the applicable value's provenance.

Apply each accepted correction atomically against its base revision. Reject or
reanalyze stale results instead of overwriting newer edits. Before/after photos
and messages are interpreted against the current meal, so a previously applied
half-portion correction is not applied a second time by accident.

## Architecture and migration boundary

Recommended, conditional architecture: an iPhone client owns durable local
records and a persistent submission queue. A device worker performs authorized
inference. Private cloud backup synchronizes locally persisted records, including
pending captures, and retained photos independently of inference. Backup and
inference status are separate. A restored pending capture may resume analysis
only after its owner has reauthorized the provider connection.

The alternative is an iPhone client with a hosted analysis worker. It improves
continuation after the phone stops running, but adds hosting, credential handling,
and subscription-eligibility dependencies. It remains a future option.

Use one provider-independent analysis operation with an explicit versioned input
and output schema. Input contains submission/meal identifiers, intent, base
revision, relevant current items, selected photo content, message, language,
and applicable dietary context. It contains no authorization tokens or unrelated
diary history. Output is an item proposal with quantities, nutrient provenance,
uncertainty, and clarification needs. Validate identifiers, units, numeric values,
and the schema before committing. The analyzer never directly writes diary data.

Provider transport, credential access, and the worker's execution location stay
outside the calculation and revision logic. A later server implementation can
accept this contract and return proposals without redesigning the screens or
meal records. A server must derive ownership from authenticated sessions and
enforce it; client-supplied IDs do not establish permission. Do not build a
server framework or unused transports now. Moving credentials or inference to
a server requires a fresh eligibility/security review; code portability does
not transfer provider authorization.

Use Swift with SwiftUI as the recommended native presentation layer. Keep
calculation, revision validation, day assignment, and the analysis contract in
plain Swift types independent of views and provider SDKs. Use structured
concurrency for the device worker, protected Keychain credential storage, and
native camera/photo-library access. Select durable storage and private backup
together at the feasibility gate so recovery semantics remain consistent.

Cloud identity, backup provider, signing/distribution, and minimum supported
iOS version remain gated decisions. The main capture/editing flow must remain
usable when optional Siri features are unavailable. Availability checks isolate
iOS 27 features instead of making beta Siri a prerequisite for opening the diary.

## Implementation standards

Use ponytail's default full level: the smallest complete solution, with clear
control flow, descriptive names, and focused functions. Prefer native frameworks
and the standard library; add dependencies only when they solve a substantial
need. Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/),
prioritizing clarity at call sites over character count. Use value types where
appropriate, explicit optional/error handling, and structured concurrency with
correct isolation of UI and shared mutable state. Do not hide failures with
forced unwraps or discarded errors in normal user flows.

Keep the requested analysis/server migration boundary, but omit unused wrappers,
generic repositories, speculative configuration, and abstractions around every
type. Comments explain non-obvious reasons; meaningful tests cover calculations,
day boundaries, retries, revisions, and data ownership. Minimal code must retain
validation, durable recovery, security, and accessibility. Record material known
limits and report checks actually performed.

## Frontend design guidance

The owner requested [taste-skill](https://github.com/Leonxlnx/taste-skill/blob/main/skills/taste-skill/SKILL.md),
read on 2026-10-11. Its stated scope is marketing websites, and its native-mobile
exclusion directs developers to Apple HIG. Apply relevant visual principles as
supplementary guidance; [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/)
and native SwiftUI conventions govern the app's platform behavior.

Before UI work, state the design read and establish a small consistent set of
type, spacing, color, and shape choices. Use clear hierarchy, purposeful motion,
concise labels, and complete empty/pending/error states. Validate light/dark
appearance, readable contrast, Dynamic Type, VoiceOver, Hebrew RTL, reduced
motion/transparency, and touch targets. Styling must support fast capture and
visible processing/backup status.

Use native controls and SF Symbols where suitable. Web framework, CSS, icon
package, hero-layout, and scroll-animation prescriptions do not change the
Swift stack or add marketing surfaces. Do not hide useful diary data or add
visual effects solely to satisfy a website rule. Ponytail remains the code
simplicity standard; visual polish does not justify speculative UI frameworks.

## Native Siri integration: proposed scope and research

The owner requested research into iOS 27 Siri AI beta. Recommendation for review:
start with three explicit App Intents/App Shortcuts: Log meal with text, Log
weight with a numeric value/unit, and Start new day. They call the same app
operations as the screens. Meal logging acknowledges durable capture as queued,
not completed analysis. Day ambiguity can open the app for its existing question;
voice invocation must not silently choose a different day rule. Handle retried
execution without introducing duplicate records. Validate the exact invocation
phrases, parameter collection, locked-device behavior, and queue persistence on
a physical phone before advertising hands-free completion.

Richer requests such as asking about today's meals, correcting a selected meal,
or importing a photo from another app remain later feasibility candidates.
The [schema catalog](https://developer.apple.com/documentation/appintents/app-schema-domains)
has no dedicated food/nutrition domain. Broad natural-language Siri action
routing relies on supported schemas; custom shortcuts alone do not establish
that arbitrary meal commands will work. Adopt genuine matching camera, photo,
or system-search capabilities where useful; never label a nutrition record as
an unrelated schema just to obtain routing. Onscreen entity annotations and
Transferable may help contextual requests, subject to device tests. See
[Apple's Siri session](https://developer.apple.com/videos/play/wwdc2026/240/).

[Apple's user guide](https://support.apple.com/en-my/guide/iphone/iphv6zwrg8jvfgr/27/ios/27)
currently describes Siri AI beta for iOS 27+, initially in English, on iPhone
15 Pro/Pro Max and iPhone 16 or later with Apple Intelligence enabled. Initial
EU restrictions and usage limits apply. Hebrew is not listed as supported for
Apple Intelligence. App language/input support remains independent; check actual
phone, region, system language, and feature availability during the gate.

Separately, iOS 27 Foundation Models supports image input for Apple's on-device
and Private Cloud Compute models. This could support a later alternative
analyzer, evaluated on food recognition, portion estimates, label extraction,
Hebrew handling, latency, and interruption recovery. It is not an approved
replacement for the user's ChatGPT-plan requirement. See
[Apple's model overview](https://developer.apple.com/documentation/foundationmodels?changes=l_3)
and [PCC integration](https://developer.apple.com/videos/play/wwdc2026/319/).

[PCC access](https://developer.apple.com/private-cloud-compute/) requires Small
Business Program enrollment, fewer than two million first-time downloads, and
an assigned managed entitlement. Eligible developers have no cloud API token
cost, but users face daily quotas; membership/distribution costs and our actual
eligibility are unverified. Do not promise free unlimited inference or apply
for paid membership without approval.

Foundation Models' third-party provider protocol does not itself authorize
ChatGPT plan use. Providers still implement authentication and credential
handling, as described in [Apple's provider session](https://developer.apple.com/videos/play/wwdc2026/339/).
The reviewed Apple sources do not establish a Siri-to-app route for borrowing
the user's ChatGPT session/subscription. Preserve the existing official OpenAI
authorization gate and never silently substitute an Apple or paid API provider.

## Privacy and ownership

Keep meals, photos, weights, and backup objects private to their owner. App data
identity is independent of the provider connection: lost plan access must not
erase history or block direct editing. Account switching isolates records,
credentials, and queues; never dispatch another account's job with the active
account's token. Email alone is not a sufficient identity boundary.

Store credentials in protected OS storage, outside ordinary diary backup.
Never log credentials, raw prompts, meal photos, weights, signed private URLs,
or food descriptions. Send only the context needed for each request. Imported
copies can remove location metadata without modifying the user's photo library.

Show backup pending versus acknowledged backup. Offline or unbacked records
cannot be promised recoverable after phone loss. Sign-out hides account data,
clears/revokes provider sessions appropriately, and preserves unsynced records
in isolated protected storage for that owner to recover. It does not silently
discard unsynced data or expose it to the next account.

Export records and attached photos in a portable JSON-plus-media archive without
credentials. Explicit photo/meal deletion propagates to local storage and cloud
backup and invalidates related jobs; tombstones prevent stale backup or inference
results from resurrecting content. Account deletion includes profile, meals,
photos, and weights. Do not delete unrelated photos or provider conversations.

## Verified documentation and unresolved dependencies

Checked on 2026-10-11. These are documentation findings, not successful account
authorization, device tests, deployments, or inference results.

- [Availability](https://developers.openai.com/siwc/quickstart) and the
  [overview](https://developers.openai.com/siwc/token-sharing-open-source): plan
  usage has eligibility constraints. Paid/hosted offerings use the interest
  process. Open source alone does not validate our phone architecture.
- [Official example](https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt):
  describes open-source tools and local personal projects. The pilot's exact
  eligibility and native compatibility must still be established.
- [Authorization](https://developers.openai.com/siwc/token-sharing-open-source/sign-in):
  PKCE, state, nonce, ID-token validation, a stable host ID, and an issued
  per-registration client ID are required. The documented callback is HTTP
  loopback at 127.0.0.1. Plan use needs separately granted scopes; identity
  sign-in alone is insufficient. A supported iPhone callback is not verified.
- [Inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference):
  discover models for the selected account and call POST /v1/responses with its
  OAuth token. Use store:false and stream:true; success requires completed
  inference. No particular model is guaranteed available to our account.
- [Preview limits](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations):
  images are accepted by compatible models; audio/video and Files uploads are
  unsupported. HTTP requests supply their own context; persistent provider
  conversation storage is not the diary. Listed unsupported fields/tools must
  be excluded. No access to existing ChatGPT conversations or memories is granted.
- [Tokens](https://developers.openai.com/siwc/token-sharing-open-source/token-reference)
  and [sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions):
  tokens require renewal; current docs specify one-hour access and rotating
  30-day refresh tokens. Serialize refresh and replace the token set atomically.
- [Recovery](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery):
  handle quota, ineligibility, route restrictions, temporary failures, and
  terminal refresh errors distinctly. Revocation is not delivered as a push
  notification. Never silently switch billing or infer a quota reset time.
- [Apple background work](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask):
  user-started work can continue in the background but can be canceled or
  terminated. Durable recovery is required; execution is not guaranteed.

The integration gate requires an officially supported path, validated device
behavior, account-specific model/image access, and applicable admission in the
owner's region/workspace. Absence of a documented native recipe is uncertainty,
not proof that all native approaches are impossible. Never bypass requirements
with browser cookies, scraping, shared credentials, or another application's
credentials. If no supported route meets iPhone-only operation, report the exact
blocker and obtain a new product decision before changing the requirement.

Costs are not verified. The USD 0 preferred / USD 10 monthly ceiling must include
the selected backup capacity and any supporting runtime. Retained photos drive
storage growth. Identify signing/distribution fees separately from monthly
infrastructure. Subscription inference consumes the user's authorized plan
allowance and any provider-enabled credits under their settings; no unlimited
usage or zero incremental provider cost is promised. Never buy credits, enable
billing, or substitute paid API access without explicit approval.

## Staged delivery and observable acceptance

These milestones describe scope; they are not an approved implementation plan.

1. **Integration proof and technology decision.** Establish official eligibility;
   demonstrate fresh per-app authorization entirely on iPhone, a real synthetic
   image request, validated completion, token renewal, denial/revocation/quota
   handling, and background interruption recovery. Never reuse existing app
   credentials. Validate native Swift feasibility and select durable storage,
   backup identity/provider, distribution path, minimum iOS, and verified costs.
   If supported authorization cannot be established,
   stop product implementation and document the blocker. Failure states may be
   fault-injected when live reproduction is impractical; label that evidence.
2. **Local diary.** Photo/text/both capture persists before acknowledgment;
   offline relaunch retains it. Synthetic analysis is visibly demonstration
   mode. Quick/review modes, direct editing, language switching, and photo
   attachments work without duplicating meals.
3. **Live logging and corrections.** Authorized analysis commits validated item
   proposals; half portions, less rice, diluted sauce, and before/after photos
   update one meal. Stale responses cannot overwrite newer edits. Totals are
   recalculated from saved records after edits, moves, and deletes.
4. **Days and history.** A 04:00 meal can stay on the preceding waking day;
   explicit waking actions and expired day confirmations are tested. Missing
   weights do not freeze days. Complete/Partial/Untracked/Unknown remain distinct.
   DST/timezone changes and unknown nutrient values do not invent intake.
5. **Private restore and pilot.** Acknowledged backup restores photos and records
   on a fresh installation. Two synthetic accounts cannot see each other's
   data/jobs. Export, deletion, logout with unsynced work, and tombstone behavior
   pass. Validate Hebrew RTL, English, large text, VoiceOver, reduced motion,
   and physical-device offline/background behavior. Run the 14-day personal pilot.

Use synthetic food/label/photos and accounts for fixtures, logs, and shared test
artifacts. Record command, timestamp, environment, source commit, result/counts,
and remaining gates. Distinguish local, simulated-failure, live-provider,
physical-device, backup-restore, and pilot evidence. Unavailable checks are
blocked or not run, never passed.

If the proposed Siri shortcuts are selected, include physical-device evidence
for text capture, numeric weight/unit handling, explicit day start, ambiguous
day handoff, denied access, offline capture, and retried execution. Optional
iOS 27 features must fail gracefully while the ordinary diary stays usable.

## Review and next step

The written review includes recommended SwiftUI presentation, the proposed basic
Siri shortcut scope, four-hour day-confirmation expiry, privacy/export behavior,
basic totals versus deferred scoring, and acceptance criteria in addition to
the already approved flow, native Swift direction, and conditional architecture.
After written-spec approval, create the implementation plan and obtain approval
of that plan and its execution method. No product implementation starts before
those reviews. No provider signup, external message, paid resource, or public
publication is performed by writing this document.
