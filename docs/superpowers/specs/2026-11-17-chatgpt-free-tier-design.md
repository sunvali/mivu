# ChatGPT accounts that can't use their plan (Free tier)

Date: 2026-11-17. Platforms: iOS and Android, shipped as two separate PRs.

## Why

A real user signed in with a Free ChatGPT account. Mivu showed "Enable ChatGPT plan
usage", which read as something they could fix, so they kept trying. Nothing told them
the failure was because of their plan. The owner is fine with such a user staying
signed in even though Mivu can never use ChatGPT for them; what matters is that they
understand why and can keep using the app.

## Facts this design rests on

- Mivu uses OpenAI's Sign in with ChatGPT plan usage (`api.openai.com/v1`, scopes
  `resource.invoke chatgpt.tokens.use.direct`), not the Codex backend.
- OpenAI states only eligible Plus and Pro users can use their plan in other apps.
  Anyone can sign in. ([quickstart](https://developers.openai.com/siwc/quickstart),
  help article 20001542.) Mivu's own store notes say "Go, Plus, Pro and Business";
  that is out of date.
- Nothing at sign-in says the plan type: no plan claim is read or documented for this
  flow. The documented signal is a Responses error
  ([errors and recovery](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery)):
  `subscription_sharing_user_not_eligible`, HTTP 403. "Explain the restriction; do not
  repeat the same request or loop through OAuth."
- Today both apps map every 403 to "plan permission missing", which pauses the account
  and shows "Enable ChatGPT plan usage" (iOS `ResponsesClient.swift` status mapping and
  `ChatGPTConnection.reflectFailure`; Android `ResponsesClient.kt`,
  `ChatGPTConnection.kt`). That is the loop the user hit.
- Unverified: what a Free account sees at the consent screen. It may grant the plan
  scope and then get the 403 above, or it may come back without
  `chatgpt.tokens.use.direct`. The design covers both.

## Goals

1. A Free (or otherwise ineligible) account learns, plainly and once, that its ChatGPT
   plan can't be used in other apps, and is never sent back through sign-in for it.
2. The app stays fully useful: the diary works by hand everywhere; on devices with an
   on-device model (Apple Intelligence on iOS, Gemini Nano on Android), photo analysis
   and Coach keep working on-device.
3. If the person later upgrades, Mivu notices without them signing out.

## Non-goals

- Detecting plan type from token claims.
- Bring-your-own-key or any paid alternative (PR #126 stays parked).
- Changing usage-limit (429) handling, which already exists.

## Anti-goals

- Any copy that implies the user can fix this inside Mivu ("Enable", "Reconnect").
- Naming specific plans in the app; OpenAI's list has changed before.
- A direct "Upgrade ChatGPT" purchase link (App Review risk, and it ties us to plan names).
- Losing a capture, message, or stored credential because of this state.

## Behavior (owner decisions)

**New state: plan not eligible.** Separate from "plan permission missing". The person
stays signed in; credentials are kept; ChatGPT counts as unavailable for inference.

**When it's detected.**
- Right after sign-in, Mivu sends one tiny text request (synthetic input only). A
  `subscription_sharing_user_not_eligible` response sets "not eligible". Success clears
  it. Temporary failures (`subscription_sharing_usage_unavailable`,
  `subscription_sharing_user_unavailable`, 5xx, offline) leave eligibility unknown and
  lock nothing.
- The same code on any later request (Coach, photo analysis, probe) also sets "not
  eligible" instead of "permission missing". The request that hit it is not retried; its
  capture or message stays saved.

**Re-check.** While "not eligible", Mivu re-checks quietly with the same tiny request
each time the app opens (launch or return to foreground), and Settings has a "Check again"
button. A Free account's rejected requests don't use any allowance. Success returns to
normal ChatGPT use without signing in again.

**Where the message shows** (devices without on-device AI):
1. Once, as a sheet right after the sign-in check finds it.
2. A lasting line on the ChatGPT row in Settings, with "Check again" and "Learn more".
3. When the person taps photo analysis or Coach: the same short explanation instead of
   an error.

Copy (draft, English only):
- Title: "Your ChatGPT plan can't be used in Mivu"
- Body: "You're signed in, but your ChatGPT plan can't be used in other apps. You can
  keep logging meals by hand. Learn more"
- "Learn more" opens OpenAI's help article "Using your ChatGPT plan in other apps and
  sites" (help.openai.com/articles/20001542). No plan names, no upgrade button.

**Devices with an on-device model** (Apple Intelligence on iOS; Gemini Nano on Android,
which already has the same provider fallback — the owner's on-device decision applies to
both). "Not eligible" makes ChatGPT unavailable, so the existing provider fallback picks
the on-device model automatically. Show one line where the provider
is shown (Settings, and the Coach/analysis surfaces' existing provider indication):
"Using on-device AI. Your ChatGPT plan can't be used in other apps. Learn more". No
sheet. When a re-check succeeds and the person never explicitly chose Apple, ChatGPT
becomes the provider again. Onboarding target tuning already falls back to the formula
estimate when ChatGPT isn't usable.

**Photos and Coach messages while AI is locked.** Reuse today's waiting behavior: they
stay saved in the existing "waiting for connection" state and resume automatically once
ChatGPT becomes usable, unless the person already entered nutrition by hand with the
existing manual entry. Only the wording changes while "not eligible": replace "Connect
ChatGPT to analyze this saved meal" and "Connect ChatGPT in Settings to continue" with
the plan explanation plus "add nutrition by hand" (meal) or the plan explanation (Coach).

**No plan scope at consent (unverified case).** If sign-in returns without
`chatgpt.tokens.use.direct`, keep today's single "Enable ChatGPT plan usage" offer. If
that consent request again returns without the scope, treat it as "not eligible" (same
copy, same re-check) rather than offering Enable again. *(Author's call, flagged for
the owner.)*

## Settled details (author's calls)

- **Error shape.** OpenAI's table names these as `error.code` in the JSON body, the
  same shape iOS already parses for the 503 codes. Read `error.code` on 403 the same
  way. A 403 without that code keeps today's handling.
- **Probe vs. missing scope.** The tiny request runs only when the plan scope was
  granted. The missing-scope path (below) is separate but ends in the same state,
  notice and re-check.
- **Persistence.** "Not eligible" is stored per signed-in registration and survives
  launch, so locked surfaces show the right copy before the re-check returns. It clears
  on sign-out or a successful re-check. A per-registration "sheet shown" flag keeps the
  sheet to once; sign-out clears it.
- **Provider.** An explicit on-device choice is the existing stored `aiProvider`
  value on both platforms; no migration. Change the provider getter so a stored ChatGPT
  choice that is "not eligible" falls back to the on-device model when it is available.
  Clearing "not eligible" restores ChatGPT with no extra record.
- **The once-only message** is a native alert like the existing "You're using your
  ChatGPT plan" welcome (iOS `.alert`, Android `AlertDialog`), with "Got it" and
  "Learn more".
- **In-app plan names.** Settings footer and onboarding say "ChatGPT Go, Plus or Pro" on
  both platforms; change to "your ChatGPT plan" wording without plan names.
- **Android error bodies.** Android never reads non-200 bodies today; read the body on
  403 only, to find the code.
- **Re-check throttle.** At most once per 15 minutes from app-open; "Check again"
  always runs.
- **Android Coach and analysis.** Same as iOS: the AI surfaces show the plan
  explanation instead of "Connect". Manual entry stays reachable as it is today.
- **Stays as is.** Tapping "Check again" with an eligible plan, or a re-check that
  succeeds, runs the normal connected path; no new success screen.

## Constraints

- Follow AGENTS.md: failing test first, XcodeBuildMCP for iOS, synthetic inputs only,
  never log token responses, durable local capture rules, English-only MVP copy,
  Dynamic Type, VoiceOver, 44-point targets.
- Android never reads `ios/` files; mirror behavior, not code.
- Keep the existing 401, 429 and 503 handling unchanged.
- Fix store notes that claim Go and Business are eligible:
  `docs/app-store/openai-plan-usage.md`, `docs/development/play-openai-plan-usage.md`.

## Evidence

- Unit tests with synthetic fixtures for: 403 `not_eligible` → not eligible (not
  permission missing); plain 403 without that code keeps today's behavior; temporary
  503 codes → unknown; re-check success clears the state; iOS provider falls back to
  Apple and returns to ChatGPT; second consent without scope → not eligible.
- A UI test per platform for the sheet and the Settings line.
- Live check with a real Free ChatGPT account is owner-only and will be reported as
  blocked until done; it also answers the unverified consent case.

## Left to the builder

- Exact names of the new state, notice, and stored flag; where the re-check hooks the
  existing lifecycle on each platform.
- The tiny request's prompt and model choice (cheapest listed model, synthetic text).
- Sheet layout following existing Mivu sheets and Apple HIG / Material.
- Whether the plain 403 (no code) should also stop showing "Enable", left as is unless
  it blocks the tests above.
