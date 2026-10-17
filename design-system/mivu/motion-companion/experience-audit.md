# Experience audit around selected Pip

Date: 17 October 2026. Source baseline: `953aa24fb15d92a0109abc773d7b16be9b391b5b`.
Scope: seven existing native iPhone journeys. This is a **source audit**, not
simulator or physical-device acceptance. No personal input or provider request
was used. The companion implementation retains Precision Glass and these flows.

## Evidence and authority

- Read all seven source surfaces below, the shared root, capture/change helpers,
  backup view, and [Precision Glass](../precision-glass/DESIGN.md),
  [components](../precision-glass/specs/COMPONENTS.md),
  [screens](../precision-glass/specs/SCREENS.md) and
  [state matrix](../precision-glass/specs/STATE-MATRIX.md).
- Visually inspected the existing paired light/dark
  [Today concept](../precision-glass/assets/01-today.png) and selected
  [Pip identity](../characters/pip/reference.png). These are illustrations;
  drawings do not establish runtime control geometry or color contrast.
- [Earlier simulator evidence](../../../docs/implementation/precision-glass-verification.md)
  is historical, tied to its stated revisions. Its local screenshot directory
  is absent from this checkout. It cannot substitute for the new baseline run.
- **Simulator-observed in this audit: none.** Root integration verification
  owns fresh baseline/candidate captures and native interactions. Every source
  finding below needs that check before being called a runtime defect.
- [Approved companion spec](../../../docs/superpowers/specs/2026-10-17-motion-companion-design.md)
  and [Pip motion bible](../characters/pip/MOTION.md) govern the bounded change.
  The [roadmap](experience-roadmap.md) and
  [proposed experience spec](../../../docs/superpowers/specs/2026-10-17-experience-redesign.md)
  do not authorize replacement journeys.

## Platform assessment

Source structure is native: labeled TabView destinations, NavigationStack,
Form/List, system menus, sheets, pickers and SF Symbols. No custom global bar
or intercepted back gesture was found in these seven surfaces. Settings is
presented in a root sheet containing its own navigation stack, preserving the
originating tab. This differs from the older written push-only description;
retain current behavior during Pip integration.

| Dimension | Source evidence | Current acceptance |
| --- | --- | --- |
| Accessibility | System text styles, scalable metric, combined day rows, labeled icon controls and explicit minimum heights in many controls | Not scored: VoiceOver order, all target widths and largest-text reachability unobserved |
| Performance | Stable Coach row IDs and explicit history paging; photos decoded in meal detail body, analytics computed from snapshots | Not scored: no traces, launch timing, memory or device scroll samples |
| Appearance | Shared semantic colors and native control materials; one composer error uses `.red` | Not scored: actual composited light/dark and contrast modes unobserved |
| Platform behavior | Four destination tabs; system navigation, input and modal controls | Source conforms structurally; keyboard/back/sheet behavior unobserved |
| Adaptivity | ViewThatFits/stack alternatives on Today, Diary and Progress; Coach has accessibility composer variant | Not scored: small phone, landscape and largest text unobserved; no iPad acceptance claim |

## Seven journey inventories

### J1 Today and saved receipt

Source: [TodayView.swift](../../../ios/Mivu/Diary/TodayView.swift),
`DiaryRootView` and `TodayView`; [DiaryViewModel.swift](../../../ios/Mivu/Diary/DiaryViewModel.swift),
`capture` and `change`.

- Entry/exit: selected Today tab after local profile load; Log meal opens J2;
  meal or saved receipt opens J3; profile button opens J7 and returns here.
- Primary action: bottom safe-area Log meal. Optional weight, dated goal,
  day actions and explicit coverage remain separate actions.
- States: root shows Opening diary during initial load; no profile shows
  setup; empty meals retain Log meal; populated ledger shows exact record IDs.
  Pending count and unknown totals do not masquerade as completed estimates.
  Save receipt says Saved on this iPhone, linking to the persisted meal.
  Offline analysis does not remove capture access; errors use the root alert.
- Friction: date is a canonical local-date string rather than the concept's
  readable weekday/date. Receipt has no visible analysis-state subtitle on
  Today (day-detail receipt does). These are clarity opportunities, not a
  reason to replace the root. Pip must fit the existing summary hierarchy.
- Accessibility/data: safe-area action and wrapping goal fallback exist;
  companion must stack above the date at accessibility sizes. Receipt resets
  on profile change. Save receipt is emitted after store write and refresh;
  no animation may imply that backup or analysis completed.

### J2 Capture and waking-day choice

Source: [MealComposerView.swift](../../../ios/Mivu/Diary/MealComposerView.swift).

- Entry/exit: Today, historical day, or Add note or photo on an existing meal.
  Save returns to origin after successful local capture; Cancel asks before
  discarding a valid note/photo draft. Correction targets the existing ID.
- Primary action: toolbar Save; disabled for empty draft, submission and photo
  preparation. Note, photos, day context and review-first toggle precede it.
- States: empty instructions; populated draft; photo preparation and import
  failure retaining other input; saving spinner; failed save stays in editor.
  Ambiguous day offers Previous day / New day / Keep editing. Offline capture
  is local-first; waiting/retry belongs to the saved record. Photo permission
  and camera behavior require separate runtime checks of `PhotoInput`.
- Friction: the review-first wording combines two distinct commits (capture
  and accepted totals). Explain them in place before proposing a new screen.
  Source error text uses `.red`, unlike semantic `diaryError` elsewhere.
- Accessibility/data: scrolling keyboard dismissal and Done toolbar exist.
  Largest-text photo controls, keyboard-safe Save and waking-day dialog need
  observation. Draft is view state, so interruption/termination is not proven
  to restore an unsaved draft. Existing submission ID and saving guards must
  remain intact; a decorative gesture must never delay the commit/dismissal.

### J3 Meal review and correction

Source: [MealDetailView.swift](../../../ios/Mivu/Diary/MealDetailView.swift),
`MealDetailView`, `FoodItemEditor`; J2 for appended evidence.

- Entry/exit: exact-ID receipt or row in Today, Coach or Diary. Back returns
  to origin. Ingredient editor saves the selected item/revision; Add note or
  photo appends a submission; move gives a destination link; deletion confirms
  meal/photo scope and only dismisses the meal after success.
- Primary action: Mark reviewed when a proposal awaits review. Otherwise
  inspect/edit saved ingredients, append evidence or use meal actions.
- States: unavailable meal has explicit text; saved, pending, waiting for
  connection, cancelled and retry have different copy; unknown nutrients stay
  unknown. Proposal explicitly does not count in totals until accepted.
  Connection opens J7. Failures remain visible; stale edits use revision guards.
- Friction: successful Mark reviewed removes the proposal but has no dedicated
  success receipt here. The approved integration adds semantic review feedback
  only after success, preserving native detail text. Add note or photo appears
  both inline and in the action menu. Record history accurately warns that
  full before/after values and individual change timestamps are not recorded.
- Accessibility/data: dynamic text and scoped confirmations are present;
  ingredient/quantity errors, photo reader order and deep-sheet dismissal
  need native checks. Never implement rollback or fabricate audit history.
  Do not celebrate a passive refresh, failed review or wrong-profile commit.

### J4 Coach capture, retry and history

Source: [CoachView.swift](../../../ios/Mivu/Coach/CoachView.swift),
`composer`, `turnActions`, `conversationRows`, `followLatestPosition`.

- Entry/exit: Coach tab, text/photo composer; linked receipts open the same
  meal/workout IDs or the appropriate Settings destination. Earlier messages
  expands explicit history; New message resumes following latest content.
- Primary action: Send, gated by valid input and photo preparation. User input
  bubble says Input saved on this iPhone independently of the analysis reply.
- States: empty invitation; saved input/linked receipts; actual activity;
  waiting for authorization/network, needs retry and needs clarification have
  textual explanations. Retry is disabled during work. Day ambiguity requires
  explicit choice. Import and send errors stay near the draft/composer.
- Friction: several recovery reasons share Retry analysis, including missing
  authorization and clarification. A future contextual action can reduce the
  detour, but no recovery-state rewrite is required for Pip. Dense receipts
  include both a state heading and a MealRow; verify at largest text before
  proposing consolidation.
- Accessibility/data: eager loaded pages deliberately retain native accessible
  rows; do not replace with speculative lazy rendering. Reading intent, stable
  anchors, unread navigation and keyboard position must survive the fixed
  40-point companion strip. Profile change cancels photo preparation/resets
  reading state. History pagination is not proof of device memory budgets.

### J5 Diary date lookup and day detail

Source: [HistoryView.swift](../../../ios/Mivu/Diary/HistoryView.swift),
`HistoryView`, `DayHistoryView`.

- Entry/exit: Diary tab; Choose date filters saved day labels; Show all recorded
  days resets it. Day opens summary/coverage/ledger; meal opens J3. Add meal,
  weight and workout carry that selected day's context and return to it.
- Primary action: choose/open a recorded day. The implementation offers a
  date filter, **not meal-text search**; do not label that capability as shipped.
- States: no profile, no recorded days, no match for selected date and empty
  meals within an existing day have distinct copy. Local data remains usable
  offline. Historical saved receipt links to the exact meal and its state.
  Errors and saving are delegated to shared editors/root alert, not a fake
  whole-list loading screen.
- Friction: locating a remembered food requires opening dates. Meal-text
  search is a separate, deferred product decision requiring matching and
  empty-result definitions. Missing day route cannot create an arbitrary day
  merely by selecting a blank date.
- Accessibility/data: day row uses horizontal/vertical layout alternatives
  and combined accessibility. Profile change clears date filter and presented
  editors. Historical capture preserves date-only time semantics; never change
  Today's active day as a side effect of browsing history.

### J6 Progress records and reports

Source: [ProgressView.swift](../../../ios/Mivu/Progress/ProgressView.swift),
`DiaryProgressView`, weight detail and workout detail.

- Entry/exit: Progress tab; Day / 7 days / 30 days reports, text chart data,
  weight ledger, workout list/detail and goal editor. Record edits return to
  the same report/list; saved data remains available after leaving the screen.
- Primary action: inspect a period. Log weight/workout and goal editing are
  contextual actions, rather than a competing global capture action.
- States: absent day, no eligible complete samples, no saved food, missing/one
  weight measurement and empty workouts have explicit messaging. Denominators
  distinguish complete days and known nutrient samples. Missing dates are not
  zeros. Local reports work offline; editor errors must preserve their drafts.
- Friction: coverage and detailed averages sit in a disclosure; inspect whether
  the main average/denominator is understood before moving information. Nutrient
  chart is hidden from VoiceOver and has a disclosed textual data alternative.
  Accessibility of reaching that disclosure is unobserved, not assumed broken.
- Accessibility/data: report controls stack at accessibility sizes; metric
  scales; weight has table/summary and correction rows. Native keyboard,
  invalid numbers and stale correction checks belong in the candidate run.
  Pip never reacts to weight/calorie outcomes or changes analytical eligibility.

### J7 Settings profile, connection and backup recovery

Source: [SettingsView.swift](../../../ios/Mivu/Diary/SettingsView.swift),
[DiaryBackupSettings.swift](../../../ios/Mivu/Diary/DiaryBackupSettings.swift).

- Entry/exit: every root profile button or recovery link opens Settings sheet;
  destinations push inside it; Done returns to origin, guarding unsaved settings.
  Local profile selection is separate from provider account connection.
- Primary action: the chosen destination: profiles, preferences, goals, backup,
  account connection, optional nutrition source or diagnostics.
- States: no selected profile/setup; profile change disables detail actions;
  preferences conflict keeps draft and offers latest saved settings. Connection
  shows connect/permission/reauthorize, connecting+Cancel, actual model list,
  disconnect and real notice. Backup has unconfigured/pending/acknowledged/error/
  conflict states; archive read, invalid/wrong-profile and replacement/separate
  import confirmation preserve local data on failure.
- Friction: setup list puts account, backup and optional lookup side by side;
  review actual first-run comprehension before promoting connection. Cancelled
  Files pickers currently share failure wording with unreadable files; native
  observation should establish how system cancellation is surfaced.
- Accessibility/data: normal system forms and minimum row heights; long model,
  account notice and backup conflict text must wrap. Secure lookup key remains
  masked and excluded from archives. Folder write is never remote-sync proof.
  Pip preview is static; its device-local preference does not enter profiles,
  backups or provider data. Restore/delete safety remains unchanged.

## Prioritized source findings and follow-up

No P0/P1 runtime defect is established by this source-only audit. Findings are
bounded opportunities; unresolved interaction checks are separate from defects.

| ID | Priority/category | Evidence and impact | Recommendation / boundary |
| --- | --- | --- | --- |
| A1 | P2 clarity | J3 review success lacks an explicit review receipt; changed totals alone may be ambiguous | Approved successful-review semantic feedback; no new review flow |
| A2 | P2 clarity | J4 generic Retry covers authorization/clarification as well as retryable work | Deferred contextual recovery design; retain saved input and current retry |
| A3 | P2 consistency | J2 inline error uses raw red while other errors use semantic palette | Small separate semantic-color fix if native review confirms mismatch |
| A4 | P3 hierarchy | J3 repeats Add note or photo in list and menu | Deferred action hierarchy review; retain discoverability until reviewed |
| A5 | P3 readability | J1 canonical date differs from human-readable date elsewhere | Deferred date formatting; preserve canonical stored labels |
| D1 | Product decision | J5 has date lookup, no meal-text search | Deferred separate matching/index/empty-state proposal; not a regression |

Preserve local-first acknowledgement, explicit estimate/review distinction,
unknown values, coverage denominators, exact-ID navigation, scoped destructive
confirmations, draft/conflict guards and Coach reading intent. They are stronger
foundations than a replacement flow justified only by visual novelty.

## Native observation checklist still open

Use synthetic fixtures only. Capture baseline and candidate in light/dark, small
iPhone/default text, accessibility5 with keyboard, Reduce Motion, Reduce
Transparency and Increase Contrast. Record exact SHA/device/OS/configuration.
For each J1–J7 record entry, action, resulting receipt/state and return path.
Include offline text/photo capture then retry without duplication; failed save;
review then correction; long Coach history with new replies; dated historical
capture; zero-sample report; profile switch; failed archive/folder recovery.
Check VoiceOver once-only announcements and focus, and system cancellation.
Hardware remains required for haptics, camera/library permissions and performance.

This checklist does not block isolated policy/catalog work. It does block claims
that the integrated companion or a replacement journey has passed acceptance.
