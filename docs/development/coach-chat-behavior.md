# Coach chat behavior and recovery

Reviewed 2026-10-18 against the implemented Coach timeline and the approved
[design](../superpowers/specs/2026-10-18-coach-chat-history-design.md) and
[implementation plan](../superpowers/plans/2026-10-18-coach-chat-history.md).
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
  gesture settles. Failed edges require explicit retry; exhausted edges do not
  repeat reads. Load earlier/later buttons remain accessible alternatives.
- History is a recent-first list of at most 30 distinct conversation segments
  per page. A segment is identified by its stable ID, not its displayed date;
  repeated date labels can therefore remain separate. Date filters preserve
  that identity.
- The reader opens at the latest exchange. New activity follows only while the
  reader is at the bottom. When the reader browses older content, appends and
  offscreen replies preserve the visible row and expose **Jump to latest**.
  Paging, cell updates and asynchronous photo growth retain the reader's
  ownership until intentional movement, a seek, latest jump or invalidation.
- The floating **Jump to latest** control is a native glass `UIButton` owned by
  the timeline table, so a drag on it reaches the table's pan gesture. Preserve
  the table's existing accessibility-element prefix and append the button via
  [`UIAccessibilityContainer`](https://developer.apple.com/documentation/uikit/uiaccessibilitycontainer)
  methods. Keep natural Dynamic Type sizing, a target at least 44 points high,
  and focus/reader ownership off the underlying exchange. Verify an actual
  button drag and tap, natural text fit, and reader restoration within 2 points.
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

Typed receipts describe committed facts: the original target date, committed
quantities and mutation identity. Current meal status, totals, items and
availability come from a current bounded diary read. A later edit or deletion
does not rewrite the historical receipt. Diary totals continue to reflect the
current record. Unknown nutrients remain unknown, and estimated values remain
labelled.

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

The existing bounded inference context remains 14 tracking days, at most 40
eligible meals within 24 KB, 12 recent turns within 8 KB and 60 KB overall.
Those are diary-projection byte limits, not a multimodal request or token limit.
Omitted records can still be retrieved with existing tools; prior photos are
not replayed as context.

## Backups and acknowledgement

Local capture acknowledgement, committed food changes and backup-folder write
acknowledgement are separate facts. A file-provider write does not establish
remote synchronization. Keep pending errors visible and never restore stale
backup data over later captures or deletions. The bounded Coach timeline does
not reduce the completeness requirements of an explicit backup or restore.

## Evidence boundary

Current implementation and recorded evidence, including unverified device and
provider gates, are tracked in the
[Coach history verification record](../verification/2026-10-18-coach-chat-history.md).
