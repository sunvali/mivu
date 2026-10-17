# Proposed experience specification around Pip

Date: 17 October 2026. **Proposed; replacement journeys have not been reviewed.**
This is the written experience package from Task 1. It does not claim a completed
full-size screen design package or new native acceptance. The owner's approved
Pip integration proceeds within the existing Precision Glass journeys; broader
changes below are deferred until concrete design review and separate plans.

## Authority and intent

Help a person record a meal, understand an estimate and correct their own diary
without losing saved input or mistaking analysis for capture. Retain the four
native destinations: Today, Diary, Progress and Coach, each with an independent
stack. Settings opens from the profile control in a sheet with native pushed
subdestinations and Done. Log meal remains an action, not a fifth tab.

Sources: [audit](../../../design-system/mivu/motion-companion/experience-audit.md),
[roadmap](../../../design-system/mivu/motion-companion/experience-roadmap.md),
[Precision Glass](../../../design-system/mivu/precision-glass/DESIGN.md),
[components](../../../design-system/mivu/precision-glass/specs/COMPONENTS.md),
[state copy](../../../design-system/mivu/precision-glass/specs/STATE-MATRIX.md),
[approved companion scope](2026-10-17-motion-companion-design.md) and
[Pip motion bible](../../../design-system/mivu/characters/pip/MOTION.md).
The approved motion scope governs any motion-token conflict with the older
Precision Glass planning file; this proposal introduces no new duration set.

## Linked transition storyboard

Every arrow represents a user action or a real operation result, never an
animation callback. See the audit's matching J-number for source and risks.

| Path | Entry → action → result → exit | Error/escape branch |
| --- | --- | --- |
| J1 Today | Summary → Log meal → [J2](#j2-capture) → local receipt → [J3](#j3-review-and-correction) → Back to same Today | Failed capture remains J2; errors never replace saved meals |
| J2 Capture | Origin sheet → note/photo → explicit day choice if needed → Save local input → dismiss to origin receipt | Cancel dirty draft → Keep editing/Discard; import/save failure retains input |
| J3 Review | Receipt/meal → estimate/provenance → edit ingredient if needed → Mark reviewed → successful committed status → same meal | Failed/stale commit keeps editing context; connection recovery opens J7; no false success |
| J4 Coach | Composer → Send local input → saved bubble → actual processing/waiting → linked record → J3 | Retry existing saved turn; clarify target/day explicitly; earlier-history reading is stable |
| J5 Diary | Choose date/all days → recorded day → meal → J3 → Back to same date/day | No matching date explains no records; no invented zero or implicit day creation |
| J6 Progress | Period → eligible average/coverage → text/chart data → weight/workout/goal editor → updated report | No eligible data explains denominator; failed numeric save retains draft |
| J7 Settings | Origin profile button/recovery link → destination → save/connect/backup/restore result → Done → origin | Unsaved discard choice; expired auth/retry/conflict/invalid archive preserve local diary |

### J2 Capture

Keep one native sheet, toolbar Save/Cancel, note/photos, explicit waking-day
context and review-before-totals preference. Saved input and accepted totals
remain separate commits. Any future copy/layout change must show the populated
keyboard state and the previous/new-day branch, not just a pristine empty form.

### J3 Review and correction

Keep estimate label, proposed ingredient quantities and provenance adjacent to
the Mark reviewed action. Accepted totals update the same meal. Successful
review may show factual native status text and a fresh bounded Pip reaction on
return to Today/Coach. Detail itself has no mascot. Appending evidence, editing
one ingredient, changing portion, moving and deleting remain distinct scopes.
A future consolidated action menu must preserve all reachable operations and
their revision/ownership checks. Record history must describe only stored data.

## State matrix

These are requirements for any changed flow, not assertions that every state
was exercised. Use real state and existing domain errors; no fake progress.

| Journey | Default / empty | Populated | Loading | Error | Offline | Recovery |
| --- | --- | --- | --- | --- | --- | --- |
| J1 Today | No meals + Log meal; no profile routes setup | Recorded totals, goal if set, coverage, ledger | Opening diary only at root load; pending count separate | Existing actionable alert; no success gesture | Saved local records and capture available | Linked saved meal opens actual pending/retry state |
| J2 Capture | Add note/photo; Save disabled when invalid | Draft with day and review preference | Photo preparation / local save; repeated Save blocked | Couldn't save; input retained | Save locally; analysis may wait | Retry same submission; previous/new-day choice preserves draft |
| J3 Review | Meal unavailable; or saved meal without items | Estimate/provenance or committed ingredients | Actual analysis state, not an arbitrary spinner | Failed edit/review stays on record; stale revision preserved | Local inspect/edit; pending analysis explicit | Connect/retry same ID; successful reviewed status after commit only |
| J4 Coach | Invitation + one composer | Saved input, replies, exact-ID receipts | Actual processing activity; saved and processing distinct | Draft retained on failed local send; applied/not-applied exact | Waiting for network; no endless thinking | Retry saved turn / connect / explicit clarification, contextual redesign deferred |
| J5 Diary | No recorded days / no match for selected date | Coverage/day rows, date filter, day ledger | Editors own their saves; no invented list-loading delay | Shared editor/root errors leave records intact | All local lookup available | Clear filter; reopen selected day; saved receipt identifies meal |
| J6 Progress | No eligible days / missing weight/workout | Period average with sample counts, chart and text data | Only real record save; analytics not fake network activity | Validation/conflict error keeps editor draft | Local report/record access | Correct value or reopen current revision; no invented trend |
| J7 Settings | No selected profile; disconnected; no backup folder | Profile, actual provider/models, precise backup timestamp | Profile transition; connecting with Cancel; archive read; backup pending | Conflict/invalid archive/key/folder status names recoverable action | Local preferences/export available; remote auth waits | Reauthorize/retry/export copy/select correct profile; restore preview before mutation |

## Controls, tokens, status and layout

Reuse Precision Glass C01–C12. No custom tab bar, second composer, dashboard
card stack or full-screen mascot. System SF typography, semantic palette,
4-point rhythm, 20-point content inset, 44-point minimum targets and 52-point
primary actions are retained from
[tokens.json](../../../design-system/mivu/precision-glass/tokens.json).
Summary mint and chart blue stay opaque; navigation/controls use native glass.
Dark mode is authored through semantic variants, not whole-screen inversion.

Largest text: Today companion above date; summary/unit columns stack; Coach
40-point drawing remains fixed while status text and strip grow; report buttons
stack; settings values wrap. Keyboard layouts: scroll focused fields into view,
retain native Save/Cancel and numeric Done, keep composer above the keyboard,
and never move caret/scroll anchor when Pip changes pose. Test accessibility5
and small phone/default text in both appearances before accepting layouts.

| Semantic event | Visible copy contract | Pip / native feedback |
| --- | --- | --- |
| Durable capture | Saved on this iPhone / Input saved on this iPhone | One existing capture haptic; 450 ms saved gesture only after commit |
| Analysis running | Analyzing saved input / Analyzing meal | Thinking only for actual processing, 1400 ms authored loop |
| Needs review | Estimate ready to review / Needs review | No celebration for unaccepted proposal |
| Explicit successful review | Estimate marked reviewed (proposed detail receipt); preserve existing estimate provenance | 650 ms reviewed gesture when eligible; same meal only |
| Waiting / error | Your input is saved + actual connection/network/retry reason | 200 ms recovery arrival then still; recovery text owns meaning |
| Unknown nutrition | Not estimated yet / em dash + unit | Never convert unknown to zero |
| Backup acknowledgement | Saved to backup folder + time | No capture/review celebration; never claim remote synchronization |

Motion annotations: greeting once per eligible foreground session (700 ms),
attentive arrival while typing (150 ms, then still), eligible rest blink once
per 12 seconds (150 ms). Ordinary pose blends 100 ms. Motion never blocks
navigation, capture, keyboard or review. Latest fresh success only, ten-second
expiry, deduplicated by profile/operation/kind; errors and typing interrupt.
Appearance changes do not replay events. Hidden, covered, background, Reduce
Motion, Low Power or serious/critical thermal policy stops decorative work.
Pip is hidden from VoiceOver; native statuses remain accessible and announced
once. No achievement, weight/calorie judgment, sound or idle haptics.

## Visual references and review requirements

Retained references: [Today light/dark concept](../../../design-system/mivu/precision-glass/assets/01-today.png),
[Coach light/dark concept](../../../design-system/mivu/precision-glass/assets/06-coach.png),
[prior native implementation review](../../implementation/precision-glass-review.pdf),
[selected Pip identity](../../../design-system/mivu/characters/pip/reference.png),
[placement concept](../../../design-system/mivu/characters/pip/context.png) and
[acting storyboard](../../../design-system/mivu/characters/pip/storyboard.png).
These do not constitute fresh seven-journey full-size light/dark boards.

Before any replacement flow is implemented, deliver one full-size screen per
changed step in each appearance, including loading/error/offline/recovery,
largest text and keyboard. Link those screens to the J1–J7 transitions above
and record the reviewer outcome. Do not compress an entire journey into a tiny
board or substitute generated device chrome for runtime verification.

| Decision | Result |
| --- | --- |
| Selected original Pip and numerical motion contract | Accepted in existing motion brief; no new identity selection |
| Current Precision Glass journeys, tab hierarchy and local-first contracts | Retained for bounded Pip integration |
| Source journey inventory and proposed future sequence | Documented; runtime observations still separate |
| Whole-app replacement flows / search / new capture wizard / report or setup reorganization | Deferred, unreviewed and outside companion PR |
| Complete full-size screen package for proposed replacements | Pending; written paths are not visual acceptance |
| Pip front/three-quarter seven-pose production sheet, 40/64/80 pt both appearances and editable Rive rig | Asset-authoring task; concepts retained unchanged; not completed here |

No proposal becomes accepted merely because this file exists. Update the
decision ledger only after concrete journey review; then create a bounded plan
for the reviewed flow. Native candidate tests, provider acceptance, physical
device accessibility/haptics and measured Release performance remain separate
evidence gates with exact revisions and environments.
