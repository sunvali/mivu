# Android: on-device Coach with Gemini Nano

Date: 2026-10-29. Status: approved in chat by the owner and awaiting plan.

Platform: Android only, branch `docs/android-design`.

Research with sources: [.superpowers/sdd/gemini-nano-research.md](../../../.superpowers/sdd/gemini-nano-research.md). The research is gitignored scratch; this document repeats everything a builder needs from it.

## Intent

People without a ChatGPT plan can still log meals with Pip on supported Android phones. Pip runs Google's Gemini Nano on the phone. This is the Android counterpart of iOS PR #49 (`f66b8896`), the Apple Intelligence fallback, and it keeps that PR's scope and wording. ChatGPT stays the recommended, more capable Coach.

## Goals

- Logging a meal works on-device:
  - Pip turns the current message into foods with calories and macros, from text and up to 8 photos (the composer's existing cap; Nano allows 10).
  - Pip saves the meal through the normal write path.
  - The person sees the normal receipt and can Undo.
- Changing the amount in the latest meal works on-device, for example "it was half": the same `correct_item` behaviour iOS #49 supports.
- A short, simple reply. Any other request (history, weight, workouts, goals, wider edits, questions about trends) gets the iOS on-device "connect ChatGPT for this" line.
- Nutrition comes from the same bundled USDA FNDDS table iOS ships (`fndds.sqlite`, 1.7 MB, 5,431 foods, FTS5). The model picks the matching entry; Mivu does the arithmetic.
- Results are labelled estimates, exactly as on iOS.

## Non-goals

- Full Coach parity on-device. The Coach request is about 16K tokens and Nano's window is under 4K.
- Native Gemini function calling. It is a Preview feature on Nano 4, and Google's terms forbid shipping Preview features.
- Any cloud fallback, Firebase AI Logic Hybrid, or paid Gemini API. AGENTS.md forbids paid API use without the owner's authorization.
- Running Nano in the background, a job or a foreground service. Google blocks it with `BACKGROUND_USE_BLOCKED`.
- Reply notifications for on-device turns.
- An accuracy gate before release. The owner accepted iOS's state of about 21% median error, labelled as an estimate.

## Anti-goals

These would count as failure even if the feature works.

- Meal text or photos leave the phone in on-device mode.
- The on-device option appears, or half-appears, on phones that cannot run it, such as the Pixel 8 Pro, the emulator and the Galaxy S24 and S25.
- An on-device turn is lost or left stuck when the app goes to the background. It must stay pending and finish on return.
- Two saves for one message, or a committed correction applied twice. Existing receipt and replay rules apply unchanged.
- The copy presents numbers or targets as medical guidance (Google terms and Mivu rules).

## Owner decisions

- **Scope:** same as iPhone #49.
- **Play audience:** 18+. Google's ML Kit GenAI terms require it. Update the target audience in `docs/development/play-submission.md` and the owner checklist.
- **Background:** on-device turns finish only while Mivu is open. When Mivu is in the background the turn waits, Pip says it will finish when the person is back, and it finishes on return. No notification.
- **Photos:** at most 10 per message. The existing 8-photo composer cap already satisfies this. Only the current message's photos are sent; no history photos.
- **Accuracy:** ship labelled as an estimate, as iOS does. Measure later on a supported phone.
- **Testing:** a stand-in model in tests. The live check waits for a supported phone (Pixel 9 or later, Galaxy S26, recent foldables).

## How it works (decided)

### Provider choice

`ChatGPTConnection` gains a provider: `chatGPT` or `onDevice`, stored in its preferences. These rules follow iOS `Provider`:

- **Default:** ChatGPT when a ChatGPT account is saved, including while it restores. Otherwise on-device, when Nano is available.
- **No automatic switch (owner decision, 2026-10-29):** a stored on-device choice never switches to ChatGPT, even when a ChatGPT account exists and Nano reports unavailable. ML Kit beta5 reports transient errors as unavailable, so a switch could send meals to OpenAI the person meant to keep on the phone. Turns wait; Pip says "Gemini Nano isn’t ready on this phone" and points to Settings › Coach AI, which keeps the picker so ChatGPT is one tap away. This differs from iOS.
- **`canInfer`:** true for on-device whenever the model is `AVAILABLE`. It does not depend on consent.
- **`inference()`:** returns the on-device function behind the same `infer` signature the engine already uses, so `CoachEngine`, `CoachTools`, receipts, fingerprints and replay stay unchanged. The model name recorded on estimates is `gemini-nano`, the counterpart of iOS `apple-intelligence`.

### The on-device turn

Port iOS `AppleLocalInference`:

- **Input:** the current message text and up to 8 current photos, never the full Coach context.
- **First call, extraction:** returns the intent (`logMeal`, `correctLatest` or `other`), the foods with an amount and unit, and for corrections the target item and a scale or amount.
- **Grounding:** apply the iOS word-grounding rules, so foods must be grounded in the person's words or photos.
- **Second call, matching:** picks the FNDDS entry for each food from FTS5 candidates. Mivu computes the nutrients and applies the calorie floor iOS uses.
- **Building the result:**
  - The function builds one `log_food` or `correct_item` call in the ChatGPT output shape. The engine validates and applies it as usual.
  - Round 2 sees the tool output, and the on-device function returns the short iOS reply: "Done."-style text with the saved summary.
  - `other` replies "Nothing to change." with no tool call, as iOS `respondLocally` does. The limits live in a footnote under the composer while on-device is active (iOS `CoachView`): "Gemini Nano on this phone only logs meals and changes amounts, with lower accuracy. Choose ChatGPT in Settings → Coach AI for more."
- **Sampling:** greedy (temperature 0 / topK 1), as iOS does.

### Foreground only

The on-device function runs only from the foreground Coach worker path. `CoachJobService` and any background drain skip on-device turns and leave them pending.

When the app returns, the existing worker resume picks them up. `BACKGROUND_USE_BLOCKED`, `BUSY` and `PER_APP_BATTERY_USE_QUOTA_EXCEEDED` map to the existing waiting and needs-retry states with clear copy:
- `BUSY`: retry with backoff.
- Battery quota: "Pip needs a break; try later or use ChatGPT".

### Availability and download

Check `checkStatus()` before showing any on-device UI:
- `UNAVAILABLE`: show no option.
- `DOWNLOADABLE`: Settings › Coach AI shows "Download Gemini Nano" with progress, driven by the `DownloadStatus` flow.
- `DOWNLOADING`: show progress.
- Configuration still pending (`FEATURE_NOT_FOUND`): show "Getting ready…" and check again later.

### Copy and UI

Reuse the iOS #49 wording, with "Apple Intelligence" changed to "Gemini Nano" and "iPhone" to "phone":
- Settings › Coach AI lists "ChatGPT (recommended)" and "On this phone (Gemini Nano)".
- Pip's bubble and footnote copy match iOS for on-device mode.
- Settings footers copy iOS: on-device "Runs on this phone with no account, but estimates are much less accurate. It only logs meals and changes amounts; connect ChatGPT for accurate estimates, questions and other edits."
- Onboarding's connect step mirrors iOS: when Nano is available it offers "Use Gemini Nano instead" with iOS's caption, and goes straight to results. **My call:** on a `DOWNLOADABLE` phone the same button reads "Download Gemini Nano instead", starts the download and continues to results, so the provider becomes on-device once the model is ready. Unsupported phones keep "Use the estimate instead". Targets use the formula estimate, because `tunesTargets` stays ChatGPT-only as on iOS.

### Turns that change provider, and captures from outside the app

- **My call, as iOS:** a pending turn runs with the provider that is current when it runs. A person who switches to ChatGPT has chosen to send to OpenAI, and ChatGPT consent still applies. A stored on-device choice never switches to ChatGPT on its own; the turn waits until Nano answers or the person picks ChatGPT.
- **My call:** share, widget and quick-tile captures in on-device mode are accepted and saved. They wait for the foreground with the copy "Saved. Pip will finish when you open Mivu." No background run and no notification.
- **My call:** if a phone accepts text but rejects an image request, the turn goes to needs-retry with "Photos need ChatGPT on this phone; your meal is saved." The photo button is not hidden up front. Revisit this on a real device.

### Data and Play

- Meals stay on the phone.
- The ML Kit SDK sends Google diagnostic device identifiers and the configured languages. Add a "Device or other IDs / diagnostics (ML Kit)" Data safety entry and a short privacy-policy line, flagged for the owner to confirm.
- Set the target audience to 18+.

### Dependencies

- `com.google.mlkit:genai-prompt` (Beta), pinned to the exact latest version at build time. The research saw `1.0.0-beta5`; re-check. Kotlin 2.4 already meets its Kotlin 2.3+ requirement.
- Use no other new library. Copy `fndds.sqlite` from the iOS bundle into Android assets, generated once from the same source with provenance recorded. Read it with platform SQLite, which supports FTS5.

## Left to the builder

- Exact prompt text. Start from the iOS prompts and keep them under 4K tokens.
- Structured output (Alpha `@Generable` plus KSP) or plain JSON text checked with the existing strict JSON parser and one retry. **My call: plain JSON with the strict parser.** It needs no Alpha library and no KSP, and the existing trust-boundary parser handles bad output. Switch only if measured reliability demands it.
- How to inject the stand-in model for tests: an interface behind `inference()`.
- File and class names.

## Verification

- JVM tests:
  - the extraction parser and grounding;
  - FNDDS matching and arithmetic;
  - the provider defaults and fallbacks;
  - copy for each `FeatureStatus`.
- Instrumented tests use the stand-in model:
  - a meal logs end to end and is undone;
  - a correction scales the latest meal;
  - `other` asks for ChatGPT;
  - backgrounding leaves the turn pending and it finishes on return;
  - on an unavailable device the option is hidden.
- Live check on a supported phone is pending, owned by the owner. A parity row in `docs/parity.md` is marked partial until then.
