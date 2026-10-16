# Screen inventory and flow contracts
18 paired boards cover the principal surfaces. Supporting views below are specified as native component compositions, not omitted features. IDs remain stable for implementation and acceptance. Illustrations use synthetic fixture scenarios; they are not one continuous live session.

## Primary screens
| ID / board | Entry / presentation | Content priority | Main action / exit |
|---|---|---|---|
| S01 Today / 01 | Default root tab | Date, recorded intake, goal if set, coverage, pending, meal ledger, weight | Log meal -> S02; row -> S04; profile -> S13 |
| S02 Log meal / 02 | Sheet from Today or day | Notes, photos, waking day, local-save explanation | Save once -> persisted record; dismiss; failures keep draft |
| S03 Review estimate / 03 | Saved meal awaiting review | Estimate label, ingredient amounts, provenance, editable totals | Mark reviewed updates same ID; Keep estimate leaves review pending |
| S04 Meal record / 04 | Push from Today, Diary or Coach | Date/time, lifecycle, nutrition, photos, ingredients, evidence, revisions | Edit meal -> S05 or full form; more menu handles move/delete/retry |
| S05 Ingredient editor / 05 | Sheet from ingredient row | Name, amount, unit, nutrients for this amount, provenance | Save with shared validation; cancel restores original |
| S06 Coach / 06 | Root tab | Conversation, durable record receipts, analysis activity | Text/photo composer; receipt opens original record |
| S07 Diary / 07 | Root tab | Date navigation, coverage labels, recorded days | Select day -> S08; profile -> S13 |
| S08 Day detail / 08 | Push from Diary | Intake, coverage, chronological meals, weight, workouts | Add record menu: meal/weight/workout; each uses selected day |
| S09 Progress / 09 | Root tab | Period, coverage denominator, average, chart, weight/workouts/goals | Select 7D/30D; inspect metric; open S10/S11/S12 |
| S10 Weight / 10 | Push from Progress | Latest dated measurement, chart, measurement ledger | One Log morning weight action; row opens correction |
| S11 Workout editor / 11 | Sheet from day or workout detail | Type, read-only assigned date, duration, optional exercises/sets/burn | Save shared WorkoutDraft; Cancel |
| S12 Goals / 12 | Sheet from Settings or Progress | Effective date, optional targets, optional weight goal, exercise adjustment | Save dated goal; preserve earlier periods |
| S13 Settings / 13 | Push from profile button on every root | Local profile, goals, preferences, backup, connection, nutrition, diagnostics | Open grouped destination; native back returns to origin |
| S14 Backup & export / 14 | Push from Settings | Folder status/time, precise acknowledgement, export/restore actions | Native Files picker; restore preview before mutation |
| S15 Connection / 15 | Push from Settings or recovery link | Authorization state, plan limits explanation, models when available | Connect/reauthorize/cancel/disconnect appropriate to real state |
| S16 Create diary / 16 | No active local profile | Short product purpose, name field, local storage explanation | Create -> Today; Restore -> validated archive preview |
| S17 Waking day / 17 | Sheet from ambiguous capture or correction | Previous/new date options, no silent reassignment | Use selected day continues original action; Cancel keeps draft |
| S18 Waiting for analysis / 18 | State variant of S04 | Local saved receipt, pending reason, captured photo/note, unknown nutrients | Context-specific recovery; edit remains available |

## Supporting views and exact compositions
### S19 Camera
Entry: Camera in S02 or Add evidence. System permission requested only here. Native full-screen capture with Cancel/Use photo/Retake. Cancel returns to unchanged draft. Denial shows Open Settings + Add note + Photo library; no blocked diary. Photos are attached only to the currently selected target.

### S20 Photo library
System photo picker; requested selection becomes draft attachment. Cancellation changes nothing. Limited library access works without prompting for unnecessary full access. Loading/unsupported attachment errors name the item and allow removal; retain other photos and note.

### S21 Photo viewer
Push/full-screen from a meal thumbnail. Pinch/zoom and Done; meaningful photo accessibility label using stored description. Remove photo is a separately labeled destructive action with confirmation. Remove affects the selected attachment, not the meal.

### S22 Add evidence
Sheet titled "Add to Lunch", showing target date/time as read-only context. Note/photos and optional before/after role use existing enum. Save appends to that meal with revision checks. An ambiguous target must be chosen explicitly. Caption: "This will update Lunch, 16 Oct."

### S23 Meal actions
Native menu from S04: Review estimate when pending; Edit meal; Add note or photo; I ate half; Move to another day; Retry analysis when recoverable; Revision history; Delete meal. Irrelevant actions hidden, not a menu full of disabled items. Half portion acts on the existing snapshot with current revision guard; does not append a duplicate.

### S24 Move meal
Native sheet with explicit destination date/day list, current destination marked, Cancel/Move. Commit updates selected record only. Expose success with destination link; retain original on failure. Historical day labels never change as an incidental timezone side effect.

### S25 Revision history
Push from S04. Chronological revision list with time, origin (manual/Coach/analysis where known), changed fields and previous/new values. Open row to details. Read-only; do not introduce rollback if not supported. Empty: "No changes recorded."

### S26 Source details
Push/sheet from nutrition provenance. Stored source name/reference, stated portion basis and relevant values; external link only when stored. For estimate: "Estimated from the available meal details." For manual: "Entered by you." No fabricated source confidence.

### S27 Day coverage
Native picker/menu on S01/S08: Unknown, Partial, Complete, Untracked. Explain Complete means all intake recorded, not all estimates verified. Persist explicit selection. Absent day remains distinct from Unknown. Never auto-mark Complete after one capture.

### S28 Start new day
Action under Today date menu. Native confirmation: "Start a waking day?" Body: "Meals already recorded keep their original day. Starting again today reuses today's day." Cancel/Start new day. Open weight entry only if user asks; weight is optional.

### S29 Weight entry/correction
Native sheet with dated context, kg decimal field, Cancel/Save. Positive finite value <=1000 kg using existing validator, with helpful inline error. Entry starts/reuses today's waking day; correction targets the chosen existing entry/date. Do not offer unsupported unit conversion. Blank/invalid cannot save.

### S30 Workout list and detail
Progress -> dated session list -> detail. Display type, minutes, exercises, repetitions/load, estimated burn when present. Actions Edit/Delete; Add workout from list/day. Read-only detail shows "No exercise details recorded" when absent.

### S31 Exercise/set editor
Workout type is the existing Strength / Cardio / Other picker. Within S11, expanding native form sections: exercise name, ordered sets, repetitions and optional kg. Add/remove set and exercise controls 44 pt. Blank unused exercise is ignored; blank load means bodyweight. Validation: duration 1...1440 minutes; reps 1...10000; load and optional burn 0...100000; respect existing model collection/text limits. Do not replace this with a slider.

### S32 Goal periods
Settings/Progress goals link opens effective-date context/history, then S12. Empty: "No goals set" + Set goals. Targets accept blank unset or finite positive values. Switching date follows existing conflict/validation behavior and never overwrites another period silently. Display exercise adjustment as a separate value, not food intake.

### S33 Local profiles
Settings profile row -> list, selected checkmark, Create profile, Sign out, Delete selected profile. Switching cancels active work, clears wrong-owner draft, refreshes selected diary. During switch disable repeated selection and name destination. Failure retains prior safe state.

### S34 Create profile
Native sheet/alert with "Profile name", Cancel/Create. Trim and require nonblank name. Local storage explanation. No account-registration claims. Success opens selected diary; failure preserves entered name.

### S35 Diary preferences
Form: timezone, dietary preferences/restrictions, supported English language explanation. Save explicit. Validate real timezone and existing text limit 10000. A concurrent settings change preserves the draft and offers "Use latest saved settings". Explain old meals/day labels remain unchanged.

### S36 Connection states and model picker
S15 adapts: disconnected -> Continue with ChatGPT; connecting -> progress + Cancel; permission missing -> Enable plan usage; expired -> Reauthorize; authorized -> current account state, model picker populated from actual provider data, Disconnect; limit -> actual notice + Usage settings. Never hard-code model availability.

### S37 Nutrition source
Optional USDA lookup setting. SecureField, Save lookup key, configured status, Remove key. Never show/log raw secret. Caption: "Food estimates and capture work without a lookup key." Failure keeps secret masked; success clears draft per existing store.

### S38 Restore preview
Native Files archive selection -> validate -> preview current/archived profile names, replacement vs separate import. Same active profile: explicit replacement warning and stale-record protection. Different archive: import as separate if domain allows. An archive belonging to another existing local profile directs switching first. Cancel preserves all data.

### S39 Destructive confirmations
Delete meal: names meal/date and record scope. Delete profile: names profile, explains local diary deletion, suggests export before confirmation. Restore: names replacement scope. Cancel is always present. Destructive red is reserved for destructive commit. No silent account disconnect as a side effect.

### S40 Diagnostics
Support-only destination retaining existing connection diagnostic actions/results. Native grouped form, readable technical details in disclosure sections, no secrets. Close returns to Settings/Connection. Do not invent an export-log button if unsupported.

### S41 Empty diary / no profile
No records: "Your first meal starts here" + "Add a photo or a note" + Log meal; avoid fake charts and default zeros. No active profile routes to S16/profile choice, not an empty broken dashboard. No goals is a separate inline optional setup state.

### S42 Insufficient trend data
Period with zero eligible samples: "Not enough complete days" with count and link to Diary. Weight missing: "No weight recorded" + Log morning weight. One measurement shows one point and a table; do not draw a trend. Coverage and pending breakdown remain available.

## Navigation lifecycle
A new capture returns to the origin and presents a linked local receipt. A review/correction returns to the same meal. Cancel and back preserve saved records. Sheets avoid stacking other custom sheets: camera/photo picker uses system presentation; deep form substeps push inside the sheet's stack. Keyboard dismissal never commits. Sheet swipe dismissal checks dirty state. Restore or profile change invalidates any stale edit context.

## Fixture boundaries
S01/S04/S07/S08 use daily-demo. S06 uses half-portion correction scenario. S09 uses separate period-demo with five complete eligible days; it is not the partial Friday shown on Today. Do not combine these into one runtime fixture. Generated chart heights and default avatar portraits are illustrative; fixture values and native person icon are the implementation authority.
