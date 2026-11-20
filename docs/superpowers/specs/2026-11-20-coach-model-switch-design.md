# Switch the ChatGPT model from Coach: design

Date: 2026-11-20. Written against `origin/main` at `c0531726`.
Mockups: [2026-11-20-coach-model-switch-mocks.html](2026-11-20-coach-model-switch-mocks.html) (concept; emoji and the orange circle are placeholders).

## Intent

People who connect ChatGPT can already pick a model (for example "GPT‑6.2 Sol" or "GPT‑6.2 Astra") in Settings, using
the `Picker("Account model")` bound to `ChatGPTConnection.selectedModel`. The owner wants the same choice available
inside Coach, where people actually talk to the model, and wants it to stay sensible as ChatGPT releases new models.
Mivu is AI-first, so anything that can be done by hand must also be doable by asking Coach.

## Goals

1. Show the current model in Coach and let people change it there.
2. Let people change it by asking Coach in words.
3. Remember the choice across restarts. Today it resets to the first model in the catalog on every launch.
4. Move people up to newer versions of the family they chose, but never into a different family.
5. Work for every ChatGPT plan, including Go and plans that offer only one model or have no Sol or Astra.

## Non-goals

- Hints on menu rows (such as "Fast"). Show names only, exactly as the catalog sends them.
- A model choice for one chat only, or an override that applies to Coach alone.
- Any model control while ChatGPT is not connected.
- Announcing new families.

## Anti-goals (a failure even if the feature works)

- Breaking anyone's plan: picking or sending a model the account does not list.
- Moving anyone into a family they did not choose, for example a cheap new "Luna".
- Losing or duplicating a message when the model changes.
- Inventing model names or assuming that particular families exist.

## Decisions (the owner's)

### Placement
- The model name sits under the "Coach" title, as in mock A. Tapping it opens a native iOS menu listing the models from
  the account, with a checkmark on the current one.
- Coach and Settings share a single choice, so changing it in one place changes it in the other.
- When ChatGPT is not connected, or the model list fails to load or is empty, the line is hidden and the title area looks
  the way it does today.
- When the plan offers exactly one model, show its name without ▾ and without a menu.
- **Apple on-device provider** (owner, 2026-11-20). The menu lists only the models of the Coach AI chosen in Settings.
  On ChatGPT it never offers Apple; on Apple Intelligence the title shows "Apple · on this iPhone" with no menu and no
  ChatGPT models. Switching between Apple and ChatGPT stays in Settings.

### History
- The person's words and Coach's reply text are saved in history like any other exchange. The "Model changed" card
  with Undo, the "Now using … (was …)" line and the "answering again" line exist only in the current session. There is
  no new saved receipt type and no database change.

### Asking Coach
- A request such as "Use Astra from now on" changes the model. Coach replies with a "Model changed" receipt card
  (GPT‑6.2 Sol → GPT‑6.2 Astra) that has an Undo button and a VoiceOver action.
- If the request is vague ("the smarter one") or names a model the account does not list, Coach does not guess. It
  replies with the account's models as tappable choices, and nothing changes until one is tapped.

### Switching while Coach is answering
- Keep today's behavior: `TodayView` already cancels and resumes the Coach worker when `selectedModel` changes. The
  message stays saved and Coach answers again with the new model. Add a short line: "Switched to GPT‑6.2 Astra ·
  answering again". There is no popup.

### Families, upgrades and defaults
- A choice means a family (Sol or Astra), not one exact version.
- **Upgrades.** When the account lists a newer version of the remembered family, people move to it automatically. Coach
  shows one line, "Now using GPT‑6.2 Sol (was 6.1)", with Undo. Undo keeps them on the older version until the next
  version of that family appears.
- **New families.** Never chosen automatically and never announced. They just appear in the menu.
- **Default for people who never chose.** Use a family the owner sets as a new key in the existing
  `https://mivuapp.com/app-config.json`, which `AppUpdate` already fetches. If that family is not on the account, use
  the first model in ChatGPT's list.
- **Remembered family missing from the plan** (for example after a downgrade to Go). Use the first model in ChatGPT's
  list and forget the old choice. Show no note.

## Constraints

- The model list always comes from the person's own account, through `ResponsesClient.models` and its
  `visibility == "list"` filter. Never send a model the account does not list. `canCapture` already enforces this, so
  keep that check.
- iOS 26 is the minimum deployment target, so iOS 26 navigation APIs can be used.
- English only. Dynamic Type, VoiceOver, reduced motion and 44‑point targets apply, including for the title control and
  Undo.
- Follow the Coach history contract in AGENTS.md. Session-only cards and lines must not enter the diary database or
  the 100-exchange window accounting. Undo is a new change, not an edit of saved history.
- If `app-config.json` is missing or cannot be fetched, the app must still work using the first model in the account's
  list.

## Calls made during design (not owner decisions; check these)

- **The remembered choice is per ChatGPT account**, keyed by registration ID, so a Go account never inherits a Plus
  account's family.
- **When upgrades apply:** when the catalog loads. If Coach is answering at that moment, the upgrade waits until the
  answer finishes, so an upgrade never causes an unasked re-answer.
- **The default family comes from config:** add an optional key (for example `"coachModelFamily": "Sol"`) next to
  `ios` in `app-config.json`. `AppUpdate` saves the last value it fetched. On a first launch with nothing saved, use
  ChatGPT's first model. A later config value applies only to people who have never chosen a model.
- **Undo of an upgrade** shows only while the older model is still listed. If that model is gone, there is no Undo.

## Builder's call (with suggestions)

- **Parsing a family from a name (assumption).** Read `"GPT‑<version> <Family>"` from `displayName`, or the slug if it is
  more stable. A name that does not match keeps that exact model and is never auto-upgraded. Real catalog names have not
  been seen from a live account, so confirm the shape with a synthetic fixture and a real connection before shipping.
- **How the choice is stored:** suggested as `UserDefaults` keys next to `selectedRegistrationID`. Store the family, the
  exact slug, and a "held back at version" marker for Undo.
- **Title control:** `toolbarTitleMenu` together with `navigationSubtitle`, or an equivalent native control, provided the
  model stays visible after the large title collapses.
- **The Coach tool** that lets people switch by asking: it should follow the existing `CoachTools` read and write tool
  pattern.
- **Wording**, apart from the strings quoted above.

## Verification (focused, per AGENTS.md)

- Unit tests with synthetic catalogs:
  - Sol and Astra across two versions.
  - A Go-style catalog with one model and no Sol or Astra.
  - An empty catalog.
  - Names that do not parse.
  - A remembered family missing from the catalog.
  - A new family appearing.
  - A missing default family in the config.
  - The config failing to load.
  - Undo holding back an upgrade until the next version.
- A Coach test covering a clear request, a vague request and an unknown model.
- Provider cases: Apple active with ChatGPT connected; Apple only; ChatGPT only; neither. Choosing Apple from Coach
  matches Settings.
- A UI check covering the title menu with several models, one model, and no connection, plus the smoke run from
  AGENTS.md. Also have a UX review of real screenshots.
