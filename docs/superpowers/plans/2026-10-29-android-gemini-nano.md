# Android Gemini Nano Coach Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** People without ChatGPT log meals and change amounts with Pip on phones that run Gemini Nano, as iOS #49 does with Apple Intelligence.

**Architecture:**
- `ChatGPTConnection` gains a provider (`chatGPT`/`onDevice`) and a Nano status.
- For on-device, `inference()` returns a port of iOS `AppleInference.respondLocally`. It makes one extraction call, then one FNDDS pick call per food, and emits a ChatGPT-shaped `log_food`/`correct_item` call.
- `CoachEngine`, tools, receipts and replay are unchanged. On-device turns run only while Mivu is in the foreground.

**Tech Stack:**
- Kotlin 2.4.21 and Compose.
- `com.google.mlkit:genai-prompt` (Beta). Pin the latest exact version; the research saw `1.0.0-beta5`.
- Platform SQLite reading the iOS `fndds.sqlite`.

**Spec:** [docs/superpowers/specs/2026-10-29-android-gemini-nano-design.md](../specs/2026-10-29-android-gemini-nano-design.md)

## Global Constraints

- **Model name:** `gemini-nano` on estimates. The display label is "Gemini Nano".
- **Background:** Nano never runs in the background, a JobService or a foreground service. A blocked turn stays pending and finishes on return. No notifications for on-device turns.
- **Data:** the on-device path sends no meal text or photos off the phone. No cloud fallback, Firebase AI or paid API.
- **Model input:** only the current message's text and photos, never the Coach context. At most 8 photos, which the composer already enforces.
- **Sampling:** greedy (`temperature = 0f`, `topK = 1`).
- **Model output:** plain JSON text parsed strictly. A bad parse throws `ResponsesClient.Failure.Malformed`, so the engine's model-output retry applies. No `genai-schema`, no KSP and no Preview function calling.
- **Copy:** iOS #49 wording with "Apple Intelligence" changed to "Gemini Nano" and "iPhone" to "phone". The exact strings are in each task.
- **Releases:** the iOS app, `ios/version.txt` and `ios/Config/` are untouched. Android reads `ios/Mivu/Resources/fndds.sqlite` only through gradle.
- **Process:** a failing test comes before behaviour. Lint must pass, because pre-push runs it. Commit messages never mention AI tools.

## Rulings made while planning

- **FTS5:** search the FNDDS `foods` table in Kotlin, not through `foods_fts`.
  - Why: Android's platform SQLite build may lack FTS5 (the table uses `fts5` with porter). There are 5,431 rows, so loading them once is cheap.
  - Ranking: keep iOS's re-rank score (shared words, first-word hit, shorter description). Ties go by `code` instead of bm25.
  - Cost if wrong: a slightly different top-5 order for some phrases.
  - Mark it in the code with `// shortcut:`.
- **Copy for on-device waits and failures:**
  - A `waitingForNetwork` turn on-device reads "I'll finish this when you're back in Mivu."
  - A `needsRetry` turn whose `failureReason` is `OnDevice.BatteryQuota` reads "Pip needs a break. Try later, or use ChatGPT in Settings."
  - A `needsRetry` turn whose `failureReason` is `OnDevice.ImagesUnsupported` reads "Photos need ChatGPT on this phone. Your meal is saved."

## Review Focus

1. **The app goes to the background mid-turn:** Nano throws `BACKGROUND_USE_BLOCKED`, and the turn must end as `waitingForNetwork` with the on-device copy, never `needsRetry`. Pinned in Task 4.
2. **The Nano status changes while on-device is stored:** the provider falls back to ChatGPT only when a ChatGPT account exists; otherwise the turn waits. Pinned in Task 3.
3. **Food names:** a message with no photo whose foods aren't named in it logs nothing ("Nothing to change."). "make it 3" on a two-item meal changes nothing. Pinned in Task 2.
4. **Malformed model JSON** (code fences, extra fields, missing intent, negative numbers) parses or fails as `Malformed`, never crashes, and clamps numbers to 0…100000. Pinned in Task 2.
5. **The onboarding connect step on a Nano phone:** it must not auto-skip because `canInfer` is true. Only ChatGPT authorization skips it. Pinned in Task 5.

---

### Task 1: Bundled FNDDS nutrition table

**Files:**
- Modify: `android/app/build.gradle.kts`. Add a `Copy` task that puts `../../ios/Mivu/Resources/fndds.sqlite` into `build/generated/fndds/`, registered with `androidComponents.onVariants { it.sources.assets?.addGeneratedSourceDirectory(task, …) }`. Don't add all of `ios/Mivu/Resources`, which would duplicate the Pip rig.
- Create: `android/app/src/main/java/com/yakov103/mivu/analysis/NutritionTable.kt`
- Test (JVM): `android/app/src/test/java/com/yakov103/mivu/analysis/NutritionWordsTest.kt`
- Test (instrumented): `android/app/src/androidTest/java/com/yakov103/mivu/analysis/NutritionTableTest.kt`. Port the cases in `ios/MivuTests/NutritionTableTests.swift`.

**Interfaces:**
- Produces:
  - `class NutritionTable(private val file: File)` with `data class Food(val code: Int, val description: String, val kcal: Double, val carbs: Double, val protein: Double, val fat: Double)`. The values are per 100 g.
  - `companion object { fun words(text: String): Set<String>; fun bundled(context: Context): NutritionTable }`
  - `fun search(phrase: String, limit: Int = 5): List<Food>`
  - `fun portionGrams(code: Int, unit: String): Double?`
- `bundled` copies the asset into `noBackupFilesDir/fndds.sqlite` when it is missing or a different size, then opens it read-only. The foods list loads lazily once.

- [ ] **Step 1: Failing JVM test.** `words("2 Eggs and a glass of Coke")` equals `setOf("egg","and","glass","coke")`. Also `words("ok")` is empty.
- [ ] **Step 2:** `./gradlew :app:testDebugUnitTest --tests '*NutritionWordsTest'`. Expect FAIL (unresolved).
- [ ] **Step 3: Port the iOS behaviour.**
  - Words are lowercased letter runs of three or more letters, with a trailing `s` dropped unless the word ends in `ss`.
  - `search`, as in iOS: candidates share at least one term. Sort by (shared terms, first-word hit, −description length), then by `code`, and take `limit`.
  - `portionGrams` uses the iOS synonym map (`slice→slice,piece`, `glass→glass,cup`, `bowl→bowl,cup`, `mug→mug,cup`, `bar→bar,piece`). An "NFS" portion comes first, otherwise the shortest description.
- [ ] **Step 4: Instrumented test.**
  - `search("apple")` comes first with a description starting "Apple".
  - `search("")` is empty.
  - `portionGrams` for a food from a `slice` search returns a value > 0.
  - Port each `NutritionTableTests.swift` case with the same expectations.
- [ ] **Step 5:** run the JVM test, then `./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.yakov103.mivu.analysis.NutritionTableTest` on the emulator. Expect PASS.
- [ ] **Step 6:** commit `feat(android): bundle the FNDDS nutrition table`.

### Task 2: On-device turn (port of `AppleLocalInference`)

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/analysis/OnDeviceInference.kt`
- Test (JVM): `android/app/src/test/java/com/yakov103/mivu/analysis/OnDeviceInferenceTest.kt`. Port every `ios/MivuTests/AppleInferenceTests.swift` case; it uses a fake model and a fake table.

**Interfaces:**
- Consumes: `NutritionTable.Food`, `NutritionTable.words`, `CoachInferenceInput`, `CoachInferenceResult`, `CoachToolCall`, `CoachTools.namespace`, `CoachContext`.
- Produces:
  - `data class LocalTurn(val intent: Intent, val foods: List<Food>, val editFood: String?, val editQuantity: Double?)`
    - `enum class Intent { log, edit, other }`
    - `Food(name, searchName, quantity, unit, kcal, carbs, protein, fat, kcalPer100g, carbsPer100g, proteinPer100g, fatPer100g)`, all `Double` except the strings.
  - `interface OnDeviceModel { suspend fun turn(text: String, images: List<ByteArray>): LocalTurn; suspend fun pick(phrase: String, options: List<NutritionTable.Food>): Int }`
  - `interface FoodTable { fun search(phrase: String): List<NutritionTable.Food>; fun portionGrams(code: Int, unit: String): Double? }`. `NutritionTable` implements it, so JVM tests can fake it.
  - `object OnDeviceInference`, containing:
    - `const val MODEL = "gemini-nano"`
    - `suspend fun respond(input: List<CoachInferenceInput>, tools: JsonObject?, model: OnDeviceModel, table: FoodTable): CoachInferenceResult`
    - `fun parseTurn(json: String): LocalTurn`
    - `fun parsePick(json: String): Int`
- `respond` follows iOS line by line:
  - Null `tools` throws `ResponsesClient.Failure.InvalidInput`.
  - Any `FunctionOutput` in the input means the reply "Done." with no calls.
  - Context comes from the first developer message's `Context: ` marker. Texts and images come from later user messages.
  - Apply the grounding rules, then pick the latest target (the focus's `lastChanged`, otherwise the max `eatenAt` among complete meals).
  - Return a `correct_item` call with `meal_id`, `item_id`, `expected_revision`, `quantity`, or a `log_food` call with `target_local_date` and `items`.
  - Table match: try `searchName`, then `name`. A failed pick keeps the estimate. Only a weighed amount or a portion named by the person's unit is trusted.
  - Numbers are rounded to 0.1 and clamped to 0…100000. Apply the calorie floor `kcal < 0.7 × (4(c+p)+9f)`.
  - Otherwise reply "Nothing to change.".
- Output items take the ChatGPT shape from iOS `AppleInference.result`:
  - the call id is `"fc_" + callID`;
  - a message item has `output_text`;
  - a function_call item has `status: "completed"` and `namespace = CoachTools.namespace`.
- `parseTurn` accepts the JSON object, optionally wrapped in a ```json fence. Unknown fields are ignored. A missing or unknown `intent` throws `ResponsesClient.Failure.Malformed`.
- `parsePick` reads `{"option": n}` with n in 0..5. Anything else throws `Malformed`.

- [ ] **Step 1: Failing JVM tests.** Port each iOS case, plus these:
  - `logsNamedFoodWithTableNumbers`: "200g chicken breast" with a fake table hit at 165 kcal/100 g produces one `log_food` call. Its item has `kcal == 330.0` and `quantity == 200.0`, and `result.model == "gemini-nano"`.
  - `dropsUngroundedFoodsWithoutPhotos`: the model returns "banana" for the text "thanks". The text is "Nothing to change." with no calls.
  - `editNeedsNamedOrSingleItem`: "make it 3" on a two-item latest meal returns no call. On a one-item meal it returns `correct_item` with `quantity == 3.0`.
  - `functionOutputRepliesDone`: the text is "Done." with no calls.
  - `calorieFloor`: an estimate of kcal 10 with carbs 20 g, protein 0, fat 0 becomes kcal 80.
  - `parseTurnFencedAndMalformed`: a fenced valid JSON parses. `{"foods":[]}` throws `Malformed`. `"kcal": -5` clamps to 0 in the produced call.
- [ ] **Step 2:** run `--tests '*OnDeviceInferenceTest'`. Expect FAIL.
- [ ] **Step 3:** implement `OnDeviceInference.kt` as specified.
- [ ] **Step 4:** run it. Expect PASS.
- [ ] **Step 5:** commit `feat(android): on-device Coach turn`.

### Task 3: Gemini Nano model and the provider

**Files:**
- Modify: `android/gradle/libs.versions.toml` and `android/app/build.gradle.kts` to add `genai-prompt`.
- Create: `android/app/src/main/java/com/yakov103/mivu/analysis/GeminiNano.kt`
- Modify: `android/app/src/main/java/com/yakov103/mivu/connection/ChatGPTConnection.kt`
- Modify: every `canInfer` caller listed below.
- Test (JVM): `android/app/src/test/java/com/yakov103/mivu/connection/CoachProviderTest.kt`. Port the provider cases from `ios/MivuTests/CoachConnectionTests.swift` (the `appleAvailable` fixtures). Also `android/app/src/test/java/com/yakov103/mivu/analysis/GeminiNanoTest.kt`.

**Interfaces:**
- Consumes: `OnDeviceModel`, `OnDeviceInference`, `NutritionTable.bundled`.
- Produces:
  - `enum class NanoStatus { unavailable, downloadable, downloading, preparing, available }`
  - `enum class CoachProvider { chatGPT, onDevice }`, stored in the connection prefs under key `aiProvider` by enum name. An unknown value counts as unset.
  - `ConnectionState` adds `storedProvider: CoachProvider?` and `nano: NanoStatus = NanoStatus.unavailable`, plus these properties:
    - `planAuthorized`: the old `canInfer` expression, renamed.
    - `provider`: the iOS getter rules. The stored choice wins if it is chatGPT or available. If nothing is stored and (`planAuthorized` or `registrationID != null`), it is chatGPT. Otherwise it is on-device when `nano == available`, else chatGPT.
    - `canInfer = if (provider == onDevice) nano == available else planAuthorized`
    - `tunesTargets = provider == chatGPT && planAuthorized`
  - `ChatGPTConnection`:
    - `fun choose(provider: CoachProvider)`
    - `fun refreshNano()`
    - `fun downloadNano(): Flow<Float>`, progress 0..1.
    - `@VisibleForTesting internal var onDeviceForTest: OnDeviceModel?`
  - `inference()`: when `provider == onDevice` it returns `{ input, tools -> OnDeviceInference.respond(input, tools, model, table) }`. When Nano is not available it throws `SessionError.NoActiveSession`, like the ChatGPT branch.
  - `class GeminiNano(context: Context) : OnDeviceModel`, containing:
    - `suspend fun status(): NanoStatus`
    - `fun download(): Flow<Float>`
    - `companion fun failure(code: Int): Exception`
- `GeminiNano` uses `Generation.getClient()`, `checkStatus()`, `download()` and `generateContent(generateContentRequest(TextPart(…), ImagePart(bitmap)…) { temperature = 0f; topK = 1 })`.
  - Prompts: start from the iOS instructions and `@Guide` text, and ask for one JSON object with the `LocalTurn` field names. The pick prompt asks for `{"option": n}`.
  - Images are decoded with `BitmapFactory`.
  - `failure(code)` maps:
    - `BUSY` → `OnDeviceFailure.Busy`
    - `BACKGROUND_USE_BLOCKED` → `OnDeviceFailure.Paused`
    - `PER_APP_BATTERY_USE_QUOTA_EXCEEDED` → `OnDeviceFailure.BatteryQuota`
    - an image-unsupported or invalid-input code on an image request → `OnDeviceFailure.ImagesUnsupported`
    - anything else → `OnDeviceFailure.Unavailable`
  - Define `sealed class OnDeviceFailure : Exception()` in `GeminiNano.kt`.
- `canInfer` callers move as follows:
  - `MainActivity.kt:34`, the `MivuApplication.kt:120/132/149` drains and `TellCoach.kt:53` keep `canInfer`.
  - `OnboardingScreen.kt:240/294/300` change to `planAuthorized`.
  - `OnboardingScreen.kt:325` changes to `tunesTargets`.
  - `MivuApplication` calls `refreshNano()` in `onCreate`, and again from `MainActivity.onStart`.

- [ ] **Step 1: Failing JVM tests.** In `CoachProviderTest`, test the pure `ConnectionState`:
  - With nothing stored, no account and Nano available, it is on-device and `canInfer`.
  - With nothing stored and `registrationID != null` (restoring), it is chatGPT.
  - Stored on-device with Nano unavailable and ChatGPT connected: chatGPT.
  - Stored on-device with Nano unavailable and no account: chatGPT, and not `canInfer`.
  - Stored on-device with Nano available: on-device even when ChatGPT is connected.
  - `tunesTargets` is false on-device.
  - `GeminiNanoTest.failureMapping`: each ML Kit `ErrorCode` constant maps as listed.
- [ ] **Step 2:** run them. Expect FAIL.
- [ ] **Step 3:** implement. Update the callers above. Update the existing tests that build `ConnectionState` for the rename.
- [ ] **Step 4:** run `./gradlew :app:testDebugUnitTest :app:lintDebug`. Expect PASS.
- [ ] **Step 5:** commit `feat(android): choose ChatGPT or Gemini Nano for the Coach`.

### Task 4: Foreground only, and captures from outside the app

**Files:**
- Modify:
  - `android/app/src/main/java/com/yakov103/mivu/MivuApplication.kt`
  - `MainActivity.kt`
  - `coach/CoachEngine.kt` (`isTransient`, `failureReason`)
  - `coach/TellCoach.kt`
  - `ui/coach/CoachTimeline.kt` (`status`)
- Test (instrumented): `android/app/src/androidTest/java/com/yakov103/mivu/coach/OnDeviceCoachTest.kt`. It uses a fake `OnDeviceModel` through `onDeviceForTest`, with Nano forced available.

**Interfaces:**
- Consumes: `CoachProvider`, `OnDeviceFailure`, `onDeviceForTest`.
- Produces:
  - `MivuApplication.isForeground: Boolean`, tracked by an `ActivityLifecycleCallbacks` count of started activities.
  - `TellCoachOutcome.SavedOpenToFinish("Saved. Pip will finish when you open Mivu.")`
- Behaviour:
  - When the provider is on-device and the app is not in the foreground, `drainCoach` returns without running. `MainActivity.onStop` doesn't schedule `CoachJobService`. `MainActivity.onStart`'s existing drain resumes the turn.
  - `OnDeviceFailure.Busy` and `Paused` are transient, so the worker retries 1/2/4 s and the turn then becomes `waitingForNetwork`. `BatteryQuota`, `ImagesUnsupported` and `Unavailable` become `needsRetry`.
  - `failureReason` codes are `OnDevice.Busy`, `OnDevice.Paused`, `OnDevice.BatteryQuota`, `OnDevice.ImagesUnsupported` and `OnDevice.Unavailable`.
  - On-device `TellCoach` saves and returns `SavedOpenToFinish` when `canInfer`. It skips `followReply`, so no notification is sent.
  - `status()` gains the provider and the turn's `failureReason`, and uses the copy from "Rulings made while planning".

- [ ] **Step 1: Failing instrumented tests in `OnDeviceCoachTest`.**
  - `logsAndUndoes`: the fake returns a log turn for "2 eggs". A meal with `estimatedBy == "gemini-nano"` is saved, and Undo removes it.
  - `correctsLatest`: "make it 3" on a one-item meal sets the quantity to 3.
  - `otherRepliesNothingToChange`.
  - `pausedTurnWaitsAndResumes`: the fake throws `OnDeviceFailure.Paused` once. The turn is `waitingForNetwork`. A later `drainCoach(retryWaiting = true)` in the foreground completes it.
  - `backgroundDoesNotDrain`: `isForeground = false` leaves a captured turn captured.
  - `tellCoachOnDevice`: returns `SavedOpenToFinish` and posts no notification.
- [ ] **Step 2:** run the class. Expect FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run `OnDeviceCoachTest` plus the existing `CoachWorkerTest`, `CoachJobServiceTest` and `TellCoachTest`. Expect PASS.
- [ ] **Step 5:** commit `feat(android): run on-device Coach turns only in the foreground`.

### Task 5: Settings, onboarding, Coach footnote and the estimate label

**Files:**
- Modify:
  - `ui/settings/SettingsScreen.kt` (Coach AI section and row value)
  - `ui/onboarding/OnboardingScreen.kt` (connect step)
  - `ui/coach/CoachComposer.kt` (footnote)
  - `ui/meal/MealDetailScreen.kt:144` (label)
- Test (instrumented): extend `android/app/src/androidTest/java/com/yakov103/mivu/ui/` with `OnDeviceSettingsTest.kt`. Add onboarding cases to the existing onboarding UI test.

**Interfaces:**
- Consumes: `ConnectionState.provider`/`nano`/`planAuthorized`, `choose`, `downloadNano`.
- Exact copy (iOS #49):
  - Picker options:
    - "ChatGPT (recommended)"
    - "On this phone (Gemini Nano)" with the caption "No account, but much lower accuracy". It is enabled only when `nano == available`.
  - Picker footer for on-device: "Runs on this phone with no account, but estimates are much less accurate. It only logs meals and changes amounts; connect ChatGPT for accurate estimates, questions and other edits."
  - Picker footer for ChatGPT: keep the existing ChatGPT footer.
  - Nano status rows:
    - `downloadable`: a "Download Gemini Nano" button with a determinate progress bar while downloading.
    - `preparing`: "Getting ready…".
    - `unavailable`: no on-device option at all.
  - Settings row value: "Gemini Nano" when on-device, otherwise the existing value.
  - Coach footnote under the composer when on-device: "Gemini Nano on this phone only logs meals and changes amounts, with lower accuracy. Choose ChatGPT in Settings → Coach AI for more."
  - Onboarding connect step:
    - `available`: "Use Gemini Nano instead" (testTag `onboardingChooseNano`) chooses on-device and goes to results. Caption: "No account, but much less accurate. It only logs meals and changes amounts."
    - `downloadable`: "Download Gemini Nano instead" starts the download, chooses on-device and goes to results.
    - Otherwise: the existing "Use the estimate instead".
  - Meal detail label: "Gemini Nano" for `gemini-nano`.
- Touch targets ≥ 48 dp, as the surrounding rows are.

- [ ] **Step 1: Failing UI tests.**
  - Nano `available`: Settings shows both options, choosing on-device shows its footer, and the Coach shows the footnote.
  - Nano `unavailable`: no on-device text exists.
  - Onboarding with Nano available and no ChatGPT: the connect step shows `onboardingChooseNano` and doesn't auto-skip. Tapping it reaches results.
- [ ] **Step 2:** run them. Expect FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run them plus the existing onboarding and settings UI tests. Expect PASS.
- [ ] **Step 5:** commit `feat(android): Gemini Nano in settings, onboarding and Coach`.

### Task 6: Play, parity and verification records

**Files:**
- Modify:
  - `docs/development/play-submission.md`: target audience 18+. Data safety adds "Device or other IDs: collected by Google ML Kit for diagnostics, not shared, owner to confirm". Add a privacy-policy line saying on-device meals stay on the phone, and that ML Kit sends Google diagnostic IDs and configured languages. Add the owner checklist item: confirm the 18+ audience and ML Kit entry.
  - `docs/parity.md`: add the row "Coach on-device fallback (iOS Apple Intelligence / Android Gemini Nano)", partial until a live check on a supported phone.
- Create: `docs/verification/2026-10-29-android-gemini-nano.md`, with the source SHA, emulator, the commands and counts from Tasks 1–5, and "Live Nano check: blocked, no supported device (Pixel 8 Pro, emulator unsupported)".

- [ ] **Step 1:** run the parity CI script (`python3 scripts/ci/…parity…`, as the existing docs CI step does). Expect PASS.
- [ ] **Step 2:** commit `docs(android): Gemini Nano Play and verification records`.
