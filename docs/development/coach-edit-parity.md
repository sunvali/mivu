# Coach edit parity and device acceptance

This note describes the current local Coach control contract in `CoachTools`
and `CoachManualEdits`. It is development guidance for the branch, not evidence
of live provider behavior or device acceptance. The implementation keeps native
SwiftUI controls and Coach operations on the same validated `DiaryStore` actor
and record types.

## Manual controls and Coach operations

| Manual control or action | Coach read/write tools |
| --- | --- |
| Review or correct a saved/proposed meal item | `get_context`, `get_meal`, `edit_item`; `accept_review` accepts a proposal explicitly |
| Add foods to a meal or log a new meal | `append_food` for new items on a retrieved saved meal; `log_food` for a new meal |
| Review a new meal before counting it; retry paused input | `log_food` with `review_first: true`; `retry_meal` requeues the original capture |
| Move or remove a meal | `move_meal`, `delete_meal` |
| Attach or remove meal photos | `attach_photos`, `delete_photo` |
| Set a date's coverage or explicitly close it | `set_day_coverage`, `close_day` |
| Read and change dated goals | `get_goals`, `set_goals` |
| Read and change preferences or timezone | `get_preferences`, `update_preferences` |
| Start the current waking day | `get_context`, `start_day` |
| Record, correct, or remove a weight; inspect progress | `get_progress`, `log_weight`, `delete_weight` |
| Record, inspect, edit, or remove a workout | `log_workout`, `get_workout`, `edit_workout`, `delete_workout` |
| Continue an account, profile, secret, or backup action | `open_settings` creates a native Settings handoff; see below |

Operations bind to the selected local profile in app code. Meal and progress
writes validate identifiers, input bounds, ownership and expected revisions
before applying. Reads return stored records and revisions, so a correction is
grounded in the same record shown by native controls.

`edit_item` is a patch. A field omitted from the call keeps its current value;
null `name`, `quantity`, or `unit` also means unchanged. `nutrients` includes
only nutrient totals being changed; a null value clears that nutrient total.
Other nutrients, item fields, meal items and their source labels are preserved.
Changed nutrients use the same user-correction provenance rules as manual edits.
Editing a proposed review item requires its `review_submission_id` and does not
accept it. `accept_review` is a separate explicit action. Goal targets follow
the same patch rule: omitted targets stay as saved, while a null target clears
that target.

Coach writes use stable operation keys and persisted `CoachReceipt` records.
`DiaryStore.applyCoachWrites` validates the full write set, stages record and
receipt changes together, then performs one durable snapshot write before
returning receipts. A repeated operation returns its existing receipt rather
than duplicating the record. The engine supplies the committed result to the
tool response; Coach must not report a save based on model prose alone.
`append_food` groups all additions to one meal in one call per turn, as stated
in its tool description. Repeating that addition returns its existing receipt.

## Activity and native handoffs

The in-progress indicator names the current phase: preparing photos, thinking,
reading the diary, or saving changes. It exposes an accessible “In progress”
value; reduced-motion settings use a static symbol. Waiting, retry, connection,
and clarification states describe the persisted turn state. A successful
assistant completion follows the store's successful write/receipt result.

`open_settings` only returns a link in the app. The user taps it and completes
the native action. Destinations map to Settings, local profiles, ChatGPT
connection/account, nutrition-source secret, and Files backup. The tool cannot
authorize an account, delete or switch a profile, save a secret, choose a folder,
or restore a backup. Only the native screen's resulting state can establish
completion.

## Device acceptance checklist

**Merge is blocked until the owner tests this branch on a real iPhone with a real
ChatGPT subscription. Do not enable automatic merging.**

All items below remain unchecked until an owner performs and records the test
on a physical iPhone using a real ChatGPT account with an eligible subscription.
Use synthetic food and profile content; do not capture personal data in evidence.

- [ ] Install and launch the current branch build on the target iPhone; confirm
  the expected local profile is selected.
- [ ] Complete real ChatGPT account authorization in Settings and confirm the
  eligible model is available in the app.
- [ ] Ask Coach to change one field on an existing saved meal item. Confirm the
  reply reflects the committed value, then open the same meal in the manual UI
  and confirm unrelated fields and meal items remain unchanged.
- [ ] Ask Coach to clear one nutrient total and change another nutrient. Confirm
  the cleared value is absent, the changed value is saved, and omitted nutrient
  totals remain unchanged in the manual meal UI.
- [ ] Ask Coach to append one new food to an existing meal. Confirm existing
  items are not duplicated and the new item appears in the manual meal UI.
- [ ] Set and clear dated goals through Coach. Confirm the native goal editor,
  remaining budgets and historical dates agree.
- [ ] Change preferences/timezone through Coach, then inspect Settings. Confirm
  untouched fields refresh, unsaved edits survive, and conflicts cannot silently
  overwrite newer saved settings.
- [ ] Move and delete a synthetic meal; attach and delete its photo. Confirm
  History and the manual meal screen agree after relaunch.
- [ ] Request review before counting a new meal, then retry a paused capture.
  Confirm neither action creates duplicate food or counts an unaccepted proposal.
- [ ] Ask Coach to edit an unaccepted review proposal without accepting it.
  Confirm it remains a proposal until an explicit acceptance request; then
  separately accept it and confirm it enters diary totals once.
- [ ] Observe photo preparation, thinking, diary reading, and saving indicators
  during real requests; confirm wording matches the current phase and reduced
  motion presents a static indicator.
- [ ] Trigger a connection or network interruption. Confirm Coach describes a
  waiting/retry state, retains the saved input, and does not claim an uncommitted
  record was saved.
- [ ] Open each Settings handoff for account/connection, local profile,
  nutrition-source secret, and Files backup. Confirm each link lands at the
  relevant native control and Coach does not claim the action is done before
  the user completes it.
- [ ] Complete one Files backup-folder action and verify the app's local
  acknowledgement separately from any cloud-sync status.
- [ ] Relaunch the app and confirm the edited meal, conversation, and committed
  receipt-backed result remain available in the same local profile.

Simulator tests exercise local validation, persistence and fixture-driven tool
responses. They cannot prove a real account authorization, live ChatGPT tool
selection or response quality, Files-provider behavior, or physical-iPhone
interaction. The verification record below identifies the tested sources and
counts; keep every device item unchecked until it has direct physical-device
evidence.

## Local verification

Native inputs `72822ba` passed **417 unit tests, 0 failures, 1 interactive-browser
skip**. All 15 simulator workflows have covering passes: 13 passed in the full
target at app source `39066bf`; two Progress workflows passed after a test-only
keyboard-assertion correction in `72822ba`. The production app source is identical
between those two commits. This is not a claim of a new single all-target green
run after the harness correction. Exact commands, artifacts, review and remaining
gates are in the [verification record](../verification/2026-10-14-coach-edit-parity.md).
Every physical-device item above remains unchecked.

For development guidance only, see [SwiftUI Agent Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill)
and [Tool Design](https://github.com/muratcankoylan/Agent-Skills-for-Context-Engineering/tree/main/skills/tool-design).
These references are not bundled runtime tools or app dependencies and do not
need to be installed.
