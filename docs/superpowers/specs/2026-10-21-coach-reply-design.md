# Coach reply-to-message design

Status: draft for owner approval, 2026-10-21. Builds on the
[Coach chat history design](2026-10-18-coach-chat-history-design.md),
[behavior contract](../../development/coach-chat-behavior.md) and the Diary
redesign branch `feat/diary-redesign` (its `CoachNavigationRequest.target?`/`draft`).

## Why

People discuss specific things with Pip: "this toast was bigger", "what did you
mean here?". Today the only way to point at a record is retyping it, and Diary's
"Ask Pip" can only prefill text. A WhatsApp-style reply makes the subject
explicit for the person (a visible quote) and for the model (a bounded,
identified reference), so Pip edits or explains the right thing.

## Owner decisions (2026-10-21)

- Start a reply by **swiping a row right** (native swipe action, replies to
  Pip's answer in that row, or to the person's message when there is no answer
  yet) **or long-pressing a bubble** (context menu → Reply to that exact message).
- **Both** the person's and Pip's messages are repliable.
- Diary "Ask Pip" shows **only a reply quote** (e.g. "Toast · Breakfast, Tue 14
  Oct") above an empty composer with the keyboard up; no typed prefix.
- Branching was left to the builder (see Calls).

## Behavior

1. **Composer quote bar.** While a reply is set, a compact bar sits directly
   above the text field: a leading accent rule, a one-line title ("Replying to
   Pip", "Replying to you", or "From Diary"), and a one/two-line excerpt, plus an
   ✕ button (44-pt target, label "Cancel reply"). Setting a reply focuses the
   field. Sending clears it with the text; a failed or uncertain send keeps it.
   Switching profile clears it (same as draft text). It is in-memory only, like
   unsent text.
2. **Sent bubble.** A turn that carries a reply shows the same quote inside the
   top of the person's bubble. Tapping it:
   - message → existing seek/highlight path (`CoachViewModel.seek` with
     `.turn(id)`), including off-page targets and its "unavailable" outcome;
   - meal or food item → opens the current meal detail (existing
     `selectedRecord = .meal`), missing record → existing unavailable handling;
   - day → existing `.day(id)` seek.
3. **Accessibility.** The quote is part of the bubble's spoken content
   ("Reply to Pip: …"); tapping it is a button with hint "Shows the original".
   Each exchange row exposes custom actions "Reply to your message" and "Reply
   to Pip" (the latter only when an answer exists). The table's existing
   accessibility prefix and the Jump-to-latest button are untouched. Quote text
   uses Dynamic Type styles (`.subheadline`/`.footnote`), limits lines to 2 (3
   at accessibility sizes); no animation when Reduce Motion is on.
4. **Diary handoff.** `CoachNavigationRequest` gains `reply: CoachReply?`.
   When Coach consumes a request with a reply it sets the composer reply and
   focuses the field. It never replaces a reply or text the person already has
   in progress (same rule as `prefill`): an existing draft keeps its own quote.

## Data

```swift
struct CoachReply: Codable, Equatable, Sendable {
    enum Target: Codable, Equatable, Sendable {
        case message(turnID: UUID, fromPip: Bool)
        case meal(UUID)
        case item(mealID: UUID, itemID: UUID)
        case day(UUID)
    }
    var target: Target
    var excerpt: String   // display text, ≤ 280 characters, captured at reply time
}
```

- **Persistence:** `CoachSubmissionManifest.reply: CoachReply?` (optional,
  absent when nil). The manifest is already the immutable accepted-capture
  identity: reconciliation compares it, `saveTurn` refuses changing it, archives
  round-trip it, and older archives decode with nil. No schema, index or
  envelope change. `CoachExchangeSummary.reply` is read from the decoded turn the
  page query already decodes, so paging and relaunch show it with no extra query.
- **Validation** at payload creation and archive import: excerpt non-empty after
  trimming and ≤ 280 characters.
- **Immutability:** the excerpt is a snapshot of what was quoted. Later edits or
  deletion of the record do not rewrite it (like receipts). Tapping always opens
  the current record or reports it unavailable.

## Inference

The reply is real request context, not decoration (owner, 2026-10-21): the
ChatGPT request for that turn carries what is being replied to.

`CoachContext.replyTo` is set only for the turn being processed, from its
manifest; ordinary turns encode nothing new (nil is omitted). It holds:

- `target` and `excerpt` (the quote the person saw);
- for a message: the quoted turn's current `text` and `assistantText`, each
  bounded to 1024 bytes, read by id (one row), even when it is outside the 12
  recent turns;
- for a meal or food item: the current meal detail (same projection as
  `get_meal`), included only if it encodes within 8 KB; otherwise the ids alone
  and the model uses `get_meal`;
- `unavailable: true` when the quoted message or record no longer exists.

Worst case adds about 11 KB, inside the existing 60 KB context cap (the existing
trimming still applies, and the reply is kept ahead of older meals). The
developer instructions gain one sentence: when `replyTo` is present, the
person's message is about that message or record; act on it (using its real ids)
rather than guessing another, and ask if it is unavailable.

## Non-goals

- No reply threads, reply chains in the quote, or jumping between replies.
- No reply to date dividers, receipts, workouts, weights or photos individually.
- No persistence of an unsent reply across relaunch (matches unsent drafts).
- No change to Pip artwork or animation; no new dependency.
- Diary "Ask Pip" buttons themselves belong to the Diary redesign; this work
  provides the request field and composer behavior they call.

## Calls made by the builder

- **Branch:** stacked on `feat/diary-redesign` (tip `bf35b30`) because it already
  changes `CoachNavigationRequest`; the PR targets that branch and retargets to
  `main` once the Diary PR merges. `draft`/`prefill` stay for other callers.
- Swipe uses `UITableView` leading swipe actions (native, full-swipe performs it)
  and long-press uses SwiftUI `.contextMenu` on each bubble with Copy and Reply.
- Reply stored in the manifest rather than a new column, for free immutability
  and archive coverage.
- Excerpt cap 280 characters; message excerpts come from the quoted message's
  text, a photo-only message quotes "Photo".
