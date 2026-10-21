# Coach chat behavior and recovery

Reviewed 2026-10-21 against the implemented Coach timeline and the approved
[design](../superpowers/specs/2026-10-18-coach-chat-history-design.md) and
[implementation plan](../superpowers/plans/2026-10-18-coach-chat-history.md);
context behavior follows the
[Coach context design](../superpowers/specs/2026-10-21-coach-context-design.md).
The production timeline is a self-sizing `UITableView` hosting SwiftUI rows
([CoachTimelineView.swift](../../ios/Mivu/Coach/CoachTimelineView.swift)); the
existing Coach view model, diary store and worker remain the owners of capture,
queries and mutations. This adds no chat service or runtime dependency.

## Timeline and history

- The latest page and each adjacent or seek page contain at most 20 exchanges.
  The resident timeline plus reserved/in-flight page capacity is at most 100
  exchanges across five pages. A request reserves capacity before it starts;
  retired work keeps consuming the same persistent window until its underlying
  read actually exits, including after invalidation.
- Scrolling toward a measured loaded edge automatically requests an available
  adjacent page. Capacity and interaction pins can defer reservation until the
  gesture settles. Available and exhausted edges have no persistent view or
  reserved height. Loading uses a transient spinner overlay; a failed edge has
  a transient retry overlay. Exhausted edges do not repeat reads.
- The existing Chat history toolbar button exposes named accessibility actions
  for available earlier/later pages and failed-page retries. They share the
  native measured-anchor request path and capacity checks with touch paging;
  ordinary activation still opens history. Named rotor-action invocation is a
  separate manual acceptance check in the verification record.
- History is a recent-first list of at most 30 distinct conversation segments
  per page. A segment is identified by its stable ID, not its displayed date;
  repeated date labels can therefore remain separate. Date filters preserve
  that identity.
- The reader opens at the latest exchange. New activity follows only while the
  reader is at the bottom. When the reader browses older content, appends and
  offscreen replies preserve the visible row and expose **Jump to latest**.
  Paging, cell updates and asynchronous photo growth retain the reader's
  ownership until intentional movement, a seek, latest jump or invalidation.
- The floating **Jump to latest** control is a 48-point circular down-arrow
  with a spoken action label. It remains a native glass `UIButton` owned by
  the timeline table, so a drag on it reaches the table's pan gesture. Preserve
  the table's existing accessibility-element prefix and append the button via
  [`UIAccessibilityContainer`](https://developer.apple.com/documentation/uikit/uiaccessibilitycontainer)
  methods. Keep a target at least 44 points high and focus/reader ownership off
  the underlying exchange. Verify an actual button drag and tap, icon fit at
  normal/accessibility sizes, and reader restoration within 2 points.
- Ordinary startup, profile selection, refresh, capture and worker paths use
  bounded owner queries. They do not reconstruct a complete diary snapshot for
  the Coach timeline. Diary retains status metadata, not a separate transcript;
  opening Coach reads its first page once into the same persistent window.
- Diary-day navigation opens that exact day's first conversation, when present.
  A meal's **View conversation** action follows its persisted source-turn link,
  including when the meal was backdated. Missing chat, missing source and
  unavailable records remain distinct outcomes; the UI does not invent a link.

## Capture, camera and photos

The composer supports up to eight in-memory draft attachments. Draft text and
attachments are not accepted or durable until the user sends; process restart
does not restore an unsent draft. Camera opens directly from its own control,
with a separate existing-photos control. Capturing or picking a photo returns it
to the composer and never sends or creates food by itself. Access denial,
cancellation and interruption leave the composer usable.

Photo loading uses at most two global jobs and a 16 MiB decoded-image cache.
Rows hold references and load on demand; evicted content may be loaded again.
These limits describe the decoded cache and concurrent loader, not the peak
memory used while PhotosPicker transfers or normalizes an import.

Accepted capture freezes its submission identity, text, attachment identities,
capture instant, timezone and active-day context. If the save result is
uncertain, the app reconciles that same identity and immutable payload before
resending or clearing the composer. An accepted capture resumes through the
existing worker after relaunch. This is not a durable unsent-draft queue and does
not claim exactly-once remote inference.

## Receipts, history and corrections

Show one compact, immutable receipt for a committed food operation: its
original status, date, items and quantities, with Review / Edit opening current
record details. Secondary macros sit behind a native disclosure; unknown
nutrient completeness and estimation labels remain visible. Do not repeat the
current saved meal, date or nutrition as a second block. A short notice appears
only when known receipt facts differ from the current record; unrelated revision
or capture timestamps do not count as changes. Current meal status, totals,
items and availability come from a current bounded diary read. A later edit or
deletion does not rewrite the historical receipt. Diary totals continue to
reflect the current record. Unknown nutrients remain unknown, and estimated
values remain labelled.

A new consumption statement records new intake. An explicit edit of an existing
meal changes that same meal. For a clear “one more”, “another” or “same again”
about a uniquely grounded existing meal, Coach may reuse the committed item's
food and serving as an explicitly uncertain estimate. It must resolve the same
item and serving; ambiguity about the meal, item or amount is clarified instead
of guessed. Missing weight information is never invented. A grounded edit uses
the record revision it read; a concurrent edit makes that correction stale and
requires a fresh user decision. Retries reuse the original immutable receipt and
do not increment the item twice. A later manual edit remains the current value
and does not change the earlier receipt.

An unaccepted proposal is not consumed food. Current explicit amounts, labels
and visible evidence of a different item or serving take precedence over an
earlier committed portion. Read-only summaries come from current diary reads;
assistant prose alone cannot claim a saved record. A clarification is an
app-owned response for a typed missing detail and commits no food mutation.

Existing meal/photo estimation guidance remains in force: consider the current
photos and description together; estimate a visible serving first, then a
labelled typical serving or mixture when identified but not measurable. A
cocktail photo does not establish hidden alcohol or mixer amounts. Exact grams
or millilitres are not required when a reasonable uncertain estimate is
otherwise possible.

The bounded inference context is 14 tracking days, at most 40 eligible meals
within 24 KB and 60 KB overall. Those are diary-projection byte limits, not a
multimodal request or token limit. Omitted records can still be retrieved with
`get_meals_for_date`, `find_meals` or `get_meal`; prior photos are not replayed.
The request stays stateless (`store: false`).

## Conversation context

- **History as messages.** The request is the stable rules developer message,
  then up to 12 recent exchanges as ordinary user/assistant messages (1 KB per
  exchange, 8 KB total), then one tail developer message (waking-day sentence,
  `replyTo` sentence, `Context: <json>` with `recentTurns` empty), then the
  current capture. An assistant message ends with a receipt line
  `[saved key=… meal=… item=…]` for meal/item receipts, so the model has real
  ids for what it saved earlier. Weight, workout and goal receipts add no line.
- **Focus.** `focus.lastChanged` is the saved meal of the current waking day
  (`context.activeDayID`) with the highest `changedRevision`: id, revision,
  name and up to 8 item names. It covers food changes only, from Coach or by
  hand. `focus.pendingQuestion` is the previous completed turn's clarification:
  kind, candidates and the original request (1 KB). `focus` is absent when both
  are empty. A reply carries `replyTo`.
- **Resolution order.** Which record a message means: explicit mention, then
  `replyTo`, then `pendingQuestion`, then `focus.lastChanged`, then the newest
  matching meal. When one wins, Coach acts. It asks only when two candidates
  tie or before deleting a whole meal. Truncated context is not ambiguity:
  Coach uses `get_meals_for_date`, or `find_meals` for an older reference,
  then `get_meal` before editing.

## Clarification

`ask_clarification` may carry up to four candidates (`meal_id`, optional
`item_id`), validated against records Coach has seen. The question is stored on
the turn and shown as tappable chips ("Which one did you mean?"), on the true
latest exchange only. A chip sends its label with the matching record as the
reply target, so the next turn resumes the original request through
`pendingQuestion`. A clarification asked after a write finishes the turn with
the committed summary plus the question and adds no writes.

Deleting a whole meal first asks a `confirm` question, "Remove the whole <meal
name> meal?", with **Remove** and **Keep** (44 points; Remove is destructive).
They send "Remove it" / "Keep it" with the meal as reply target.

## Partial success

If a turn has committed receipts and a later step fails, the turn completes as
incomplete: the saved card stays, with "Couldn't finish the rest" and **Retry**.
Cancellation, a profile change and a failure with no receipt keep the ordinary
failure path. A network failure after a save also needs a **Retry** tap; it no
longer resumes by itself when connectivity returns. Retry sends the original
text with the turn as reply target ("Finish the rest" for a photo-only turn);
Coach does only what is missing, and committed receipts are never reapplied.

## Meal tools and Undo

- `scale_meal(meal_id, target_kcal, expected_revision)` multiplies every item
  quantity by target/current kcal, rounded to 2 decimals. It refuses a meal
  that is not accepted, has known kcal of 0, a stale revision, or a ratio
  outside 0.1–3. The manual equivalent is **Adjust total** on the meal detail,
  with a live preview. Both write the same "Direct meal scale" submission.
- `find_meals(query, from_date?, to_date?)` matches item names (ASCII
  case-insensitive), newest first, at most 10. Found meals are not editable
  until `get_meal` returns them.
- **Undo** appears on a food receipt card (log, append, edit, correct, scale,
  delete item), in the card's header row (its own row when the row is too
  narrow, after Review / Edit at accessibility sizes), and by asking
  (`undo_change`). A snapshot of the meal's saved
  items is stored with the receipt (`coach_undo`, not archived or restored).
  Undo restores it, or removes the meal a log created, and the card then reads
  "Undone". It is available only while the meal still matches its after-state
  fingerprint: revision, day, submission ids and photo ids. A later manual
  edit, capture, photo or move hides it; a stale request fails with a fresh-read
  error. There is no undo for deleting a whole meal (never restore over a
  deletion), nor for weight or workout receipts, review proposals, or an undo.

## Replies

Any message, the person's or Pip's, can be quoted: swipe a row right (replies
to Pip's answer, or to the person's message before an answer exists) or
long-press a message and choose Reply. Diary "Ask Pip" opens Coach with a quote
of the food, meal or day and an empty field; it never replaces a draft already
in progress. The quote sits inside the top of the field with a 44-point Cancel
reply control, and is unsent draft state like text.

The accepted `CoachReply` (target ids plus the quoted excerpt, at most 280
characters) is part of the immutable submission manifest, so reconciliation,
paging, relaunch and archives carry it unchanged. A later edit or deletion of
the quoted record does not rewrite it. Tapping the sent quote seeks the original
message or day through the ordinary seek path, or opens the current meal.

Only the turn being processed sends `replyTo` in its inference context: the
quoted message's current text and answer (1024 bytes each, read by id even
outside the 12 recent turns), or the current meal detail when it fits 8 KB, or
`unavailable`. Ordinary turns encode nothing new and the 60 KB limit holds.
Design: [Coach reply](../superpowers/specs/2026-10-21-coach-reply-design.md).

## Backups and acknowledgement

Local capture acknowledgement, committed food changes and backup-folder write
acknowledgement are separate facts. A file-provider write does not establish
remote synchronization. Keep pending errors visible and never restore stale
backup data over later captures or deletions. The bounded Coach timeline does
not reduce the completeness requirements of an explicit backup or restore.

## Evidence boundary

Current implementation and recorded evidence, including unverified device and
provider gates, are tracked in the
[Coach history verification record](../verification/2026-10-18-coach-chat-history.md)
and the [Coach context verification record](../verification/2026-10-21-coach-context.md).
