# Apple Intelligence Coach Option

**Goal:** People without a ChatGPT plan, App Review included, can still log meals. ChatGPT (Plus or Pro) stays the recommended and default Coach; on-device Apple Intelligence is a clearly labelled, lower-accuracy fallback.

## Current state (2026-10-23)

- **Choice:** `ChatGPTConnection.Provider` is `apple` or `chatGPT`, stored as `aiProvider`.
  - Default: ChatGPT when a ChatGPT connection is saved (also while it restores at launch).
  - Otherwise Apple when `SystemLanguageModel` is available, else ChatGPT.
  - An unavailable stored Apple choice uses ChatGPT.
- **Routing:** `ChatGPTConnection.inference()` returns `AppleInference.respondLocally` for `apple`; the ChatGPT branch is unchanged. `canInfer` replaces `planAuthorized` only where the Coach needs "can any provider answer"; with ChatGPT selected it equals `planAuthorized`.
- **On-device path** (`ios/Mivu/Analysis/AppleLocalInference.swift`): one guided generation reads only the captured message (and photos).
  - It returns intent (log, edit, other), foods, and an edit target.
  - It emits one `log_food` or `correct_item` call through the existing `CoachEngine`, `CoachTools` and receipts.
  - Logged foods and edit names must be grounded in the message's words; an unnamed edit targets `focus.lastChanged`.
  - Onboarding targets use `AppleInference.respondText`.
- **Nutrition numbers:**
  - Weighed amounts and unit-matched portions use the bundled USDA FNDDS table, with an on-device pick step choosing the entry; see [nutrition table plan](2026-10-22-on-device-nutrition-table.md).
  - Otherwise the model's estimate is used, with a calorie floor from macros.
- **UI:**
  - Onboarding keeps the ChatGPT step, recommending Plus or Pro. "Use Apple Intelligence instead" carries a lower-accuracy warning.
  - Settings → Coach AI lists "ChatGPT (recommended)" first, with Apple's lower accuracy noted on its row.
  - Coach shows Apple's limits under the input.
  - UI tests run with Apple unavailable.

## Decisions and why

- **The full Coach does not run on-device.** A real request was 16,476 tokens; the iPhone 15 Pro on-device limit is 4,096 (8,192 on an M-series Mac). Hence the slim log/edit path.
- **The Private Cloud Compute (32K) adapter was built, then removed (2026-10-23).**
  - It needs the managed `com.apple.developer.private-cloud-compute` entitlement. Without it, calls fail with `ModelManagerError 1046` while `availability` reports available.
  - Getting the entitlement requires the App Store Small Business Program, which requires the owner to accept the Paid Applications Agreement.
  - If it is granted later, rebuild from git history: commits before `feat(coach): offer on-device and Cloud …`.
- **Measured on-device behaviour** (owner's iPhone and simulator):
  - The model invents edit food names ("chocolate" for "make it three") and copies saved foods when shown them. Hence message-only prompts and word grounding.
  - Few-shot examples leaked into answers (regular Coke got the diet example's calories), so they were removed. Greedy sampling is kept.
- **Accuracy:**
  - Median kcal error is about 21% on 24 synthetic foods, against 23% model-only.
  - Published studies report similar error for large cloud models.
  - The 10% gate in the table plan is not met.
