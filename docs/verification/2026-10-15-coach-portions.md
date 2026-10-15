# Coach portion context and photo estimates

## Scope and approved design

Issue [#13](https://github.com/yakov103/mivu/issues/13), focused first slice.
The owner approved the short in-chat design on 2026-10-15: reuse a clear saved
portion for repeat food, estimate from current photos and text before asking for
exact size, retain visible uncertainty, and preserve existing context budgets.
The remaining post-save pause and broader device checks stay open in #13.

## Changes

- `DiaryStore.coachContext` admits recent meals first within the existing 24 KB
  meal budget, then restores original presentation order. Overall trimming still
  removes older retained records. Bounds, omission references and profile fences
  remain unchanged.
- Coach instructions and `log_food`/`ask_clarification` descriptions distinguish
  clear repeat portions from genuine ambiguity. Current explicit amounts, labels
  or visible serving changes override history. An unmeasurable new photo of the
  same food does not discard the saved portion.
- Current text and prepared photos already share the captured user input. That
  transport did not need changing. Visible serving estimates precede labelled
  typical serving/mix assumptions; invisible cocktail ratios remain estimates.
- App-owned food confirmations show quantities and units from the persisted
  record. Existing uncertainty and receipt grounding remain in place.

No schema, model, dependency, tool-routing system or memory service was added.
The [behavior contract](../development/coach-chat-behavior.md) contains the policy.
The [official vision guide](https://developers.openai.com/api/docs/guides/images-vision)
describes image accuracy, spatial reasoning and resizing limitations; photo
receipt alone cannot establish a precise drink volume or recipe.

## Focused local evidence

Parent: `a71a175be10de1219f95130af41ce17ee5117c8a`. Runs below used the uncommitted
delta later committed as `87c53de0867a2772cd63e535e865eb357ce1be3b`,
in `/private/tmp/mivu-local-hooks` on the local Mac / existing iOS 27
simulator through XcodeBuildMCP. Exact private arguments and artifacts are under
`/private/tmp/mivu-portion-*`; simulator identifiers are not included here.

1. An initial selector omitted Swift Testing function parentheses and selected
   **0 tests**. This is invalid verification, not a pass.
2. Correct selectors ran four tests against the old production behavior:
   **3 passed, 1 failed**, exit 1, 5.070 seconds. The receipt test failed because
   150 g, 1.5 portion and corrected 75 g were missing from confirmation text.
   The first packing fixture left enough space for its small newest record;
   that pass did not reproduce the budget bug.
3. The packing fixture was tightened to equally sized old/new projections.
   The newest 150 g yogurt was then omitted on old packing logic:
   **0 passed, 1 failed**, exit 1, 10.045 seconds.
4. After the fix, all four focused tests passed: **4 passed, 0 failed, 0 skipped**,
   exit 0, 7.633 seconds. Result: `/private/tmp/mivu-portion-green.xcresult`.

Named tests:

- `CoachStoreTests.boundedContextKeepsNewestSavedPortionAndOmissionReferencesWithoutMutation`
- `CoachStoreTests.committedFoodSummaryIncludesSavedQuantitiesAndUnitsAfterCorrectionAndRelaunch`
- `CoachEngineTests.committedHistoricalPortionReachesInferenceAndRepeatRetryPreservesReview`
- `CoachEngineTests.photoAndDescriptionShareCaptureAndCocktailComponentsStayUncertain`

The engine tests are characterization of context delivery, uncertain writes,
retained photos, unchanged unaccepted reviews and retry identity. They already
passed before policy changes and do not prove live model judgment. The original
live repeated-portion question is recorded in the prior acceptance evidence.
No test was made to simulate model improvement by checking prompt substrings.

Exact invocations use `xcodebuildmcp simulator test --json` with the private
argument files `mivu-portion-red-selected-args.json`,
`mivu-portion-context-red-args.json` and `mivu-portion-green-args.json`; output
JSON and fresh result bundles are alongside them. The focused unit run reported
no diagnostics. `/private/tmp/mivu-portion-evidence.json` records the exact source
file hashes, summaries and artifact paths, including failed/intermediate runs.

## Focused simulator workflow

`CoachUITests.testFixtureMealCorrectionHistoricalReviewAndConversationRelaunch`
passed on the same final native inputs: **1 passed, 0 failed, 0 skipped**, exit 0,
95.233 seconds. This covers the existing combined photo/text capture, saved meal,
portion correction, historical review, acceptance and conversation relaunch flow
with synthetic inference. It is not a full UI-target run or a provider test.
The command was XcodeBuildMCP `simulator test --json` using
`/private/tmp/mivu-portion-ui-args.json`; result bundle:
`/private/tmp/mivu-portion-ui.xcresult`. One non-failing diagnostic warning is
retained in the result, so this is not warning-free evidence.

## Full local unit gate

The existing `python3 scripts/ci/git_hooks.py pre-push` gate passed on source
`87c53de0867a2772cd63e535e865eb357ce1be3b`, exit **0**: **31 script tests passed**
in 21.669 seconds; **426 native unit tests passed, 0 failed, 1 interactive-browser
test skipped**. The invocation supplied the new branch's local HEAD and a zero
remote SHA, so the hook compared native inputs with `origin/main` and ran the
complete `MivuTests` target locally through XcodeBuildMCP. It did not push or
dispatch a hosted native job.

Native evidence lives in the Git common directory at
`mivu-checks/native-z23j_8zq/result.json` with `Mivu.xcresult` alongside it.
The private portion evidence file records its result summary and source. A later
documentation-only commit reuses this success only for identical native inputs,
recipe and environment. No full UI-target or physical-device pass is implied.

## Review and remaining acceptance

Independent Ponytail review checked the connected context, transport, store,
owner, correction/deletion, provenance and retry paths for one local profile with
a serialized worker. No blocking source finding remained. The developer message
stays below its 65,536-byte bound with a maximum-size diary projection.

Live observations below establish repeat portion selection for yogurt and banana.
Explicit overrides, ambiguous references, restart persistence and the owner's
cocktail photo still require device acceptance. The owner explicitly requested
merging this slice after the observed live results on 2026-10-15; those remaining
checks and the post-save pause investigation stay open in #13.

## Physical-device acceptance in progress

On 2026-10-15, the build from HEAD
`6ee2465f49a54c52195d99aae137113431ecf751` (native inputs unchanged from
`87c53de0867a2772cd63e535e865eb357ce1be3b`) compiled locally. The initial
combined install failed with a transient device connection reset; a separate
install retry and ordinary launch both succeeded. Tests use the existing owner
ChatGPT sign-in on iOS 27.0.1 and a new isolated synthetic profile,
`Portion acceptance Oct 15`; the existing diaries were preserved.

- Baseline request: “Log 150 g plain yogurt and 120 g banana for today.”
  Completed successfully. The native saved meal screen showed yogurt 150 g and
  banana 120 g on 2026-10-15: 199 kcal, 34.4 g carbs, 6.6 g protein, 5.3 g fat.
- Repeat-yogurt request: the native input displayed “E ate another yogurt.”
  (a typing artifact). Coach completed without asking for a portion. Its linked
  native saved meal showed a separate 150 g whole-milk plain yogurt estimate:
  92 kcal, 7.0 g carbs, 5.3 g protein, 4.9 g fat; uncertainty remained visible.
- “I ate another banana.” initially remained an unsent draft after Mirroring
  disconnected. After control recovered, it was submitted once. Coach completed
  without a portion question and displayed its app-owned persisted-record receipt:
  Banana (estimated), 120 g, 107 kcal, nutrition may be uncertain. Mirroring
  failed again before the linked native detail screen could be opened, so that
  additional screen inspection is not claimed.
- Explicit 75 g override, relaunch persistence, ambiguous references, and the
  owner cocktail photo remain unverified on this build.

These observations establish the baseline and two repeated-food results, not
completion of the full device checklist or all of issue #13. Private structured
observations are retained in `/private/tmp/mivu-portion-evidence.json`.
