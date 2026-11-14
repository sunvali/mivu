# Bring your own AI key (iOS)

Recorded 2026-11-14. Why: the full Coach needed a paid ChatGPT plan. This adds Claude, OpenAI, Gemini and OpenRouter on
the person's own credential. Design: [spec](../superpowers/specs/2026-11-14-bring-your-own-ai-design.md).

**No request with a real key has reached any of the four services.** The owner chose to build first and test with real
keys afterwards. Every service below is *built, not verified live*.

- Tested source: `77b8f6f19de77ae3bb9724bc76ce90e8163f632c` on `feat/bring-your-own-ai`, from `main` at `90664b9a`. The
  record's own commit changes docs only.
- Environment: macOS 27.0, Xcode 27.2 (27B52), simulator "Mivu BYO AI" (iPhone 17, iOS 27.0), XcodeBuildMCP, test plan `Mivu`.

## Results

| Scope | Result |
|---|---|
| `KeyServiceTests` (new) | failed first (types missing); 4/4 |
| `KeyServiceWireTests` (new) | failed first; 5/5 |
| `KeyServiceClientTests` (new) | failed first; 8/8 |
| `KeyConnectionTests` (new) | failed first; 15/15 |
| `OpenRouterSignInTests` (new) | failed first; 3/3 |
| Whole `MivuTests` target plus the six UI tests below, one run | 1,380 passed, 1 skipped, **1 failed**: `CoachToolsFixtureTests/fixturesMatchCurrentDeclarationsAndFingerprints` ("tools.json is stale"). It compares `CoachTools.declarations()` with `fixtures/coach/tools.json`; this branch changes neither, so the inputs are the ones on `main`. It was not re-run on `main` to confirm. Bundle `test_sim_2026-11-14T19-14-02-049Z_pid84152_e9883e46.xcresult`. |
| UI: `CoachUITests/testCoachAISettingsOffersKeyServicesAndAsksConsentFirst` (new) | failed first (services not on screen); passes |
| UI: `DiaryUITests/testSetupOffersAnotherAIBesideChatGPT` (new) | written after the link existed, so never seen failing; passes |
| UI: `CoachUITests/testChatGPTConnectAsksForSharingConsentFromCoachAndSettings`, `testOfflineTextPhotoCapturePersistsAcrossRelaunchAndTabs`, `DiaryUITests/testFirstRunOpensSetupWithoutInventingRecords`, `testLegacyHebrewLaunchUsesEnglishLeftToRight` | 4/4. With the two new ones: 6/6, in the run above. |

## Checked against the real services with a made-up key

One request per address, with the key `synthetic-not-a-real-key` and no personal data. It shows the addresses and
headers are accepted and how each service says "wrong key". It shows nothing about a working reply.

| Request | Status |
|---|---|
| Claude `GET /v1/models?limit=100` and `POST /v1/messages`, `anthropic-version: 2026-10-21` | 401, 401 |
| OpenAI `GET /v1/models` | 401 |
| OpenRouter `GET /api/v1/key` and `POST /api/v1/chat/completions` | 401, 401 |
| Gemini `GET /v1beta/openai/models` and `POST /v1beta/openai/chat/completions` | **400**, 400 ("Please pass a valid API key") |

Finding: Google answers a wrong key with 400. The key check now treats a Gemini 400 as a rejected key
(`geminiKeyCheckTreatsItsBadKeyStatusAsRejected`). A chat request keeps 400 as a plain failure, because there it can
also mean a bad request. In the app, the made-up key typed into Connect Claude shows "Claude rejected this key. Check it
and try again." ([screenshot](bring-your-own-ai/connect-claude-rejected-light.png)).

## Review

One independent review of the whole branch at `65ab5824`. No critical findings. Three fixed, each with a test that failed first:

| Finding | Test |
|---|---|
| Saving or removing a key moved the counter that guards ChatGPT sign-in, so a ChatGPT sign-in waiting in the browser could never finish or be retried | `savingAKeyDoesNotStrandAChatGPTSignInThatIsWaiting` |
| A saved model the service later dropped had no way back when the list failed to load at launch | `aModelTheServiceDroppedIsReplacedAfterItsFirstFailure`, `theModelListLoadsLaterWhenLaunchWasOffline` |
| The OpenRouter key reply was decoded as all-strings and failed on any other field | `exchangeSendsTheCodeAndVerifierAndReadsTheKey` |

Not changed, by decision: the reviewer expected an empty Claude balance to arrive as HTTP 400. Anthropic's error table
lists 402 for billing, which already maps to "out of credit". This is the first thing to check with a real Claude key.
Eight minor findings are listed in the pull request and left for the owner.

## Services

| Service | State | First thing to check with a real key |
|---|---|---|
| Claude (`claude-haiku-5-5` default) | built, not verified live | a photo meal: tool schema accepted, thinking blocks accepted when sent back |
| OpenAI (`gpt-6-luna` default) | built, not verified live | whether a plain key accepts the `namespace` tool form that ChatGPT sign-in uses |
| Gemini (`gemini-3.5-flash-lite` default) | built, not verified live | whether the tool schema (nullable type arrays, `additionalProperties`) is accepted |
| OpenRouter (`anthropic/claude-haiku-5.5` default) | built, not verified live | whether sign-in returns to a `127.0.0.1` address; if not, switch it to a pasted key |

Model ids were looked up on 2026-11-14 from each provider's models page and OpenRouter's public model list.

## Screens

Looked at in the simulator: Settings › Coach AI in [light](bring-your-own-ai/settings-coach-ai-light.png),
[dark](bring-your-own-ai/settings-coach-ai-dark.png) and the
[largest text size](bring-your-own-ai/settings-coach-ai-largest-text.png); the
[consent prompt](bring-your-own-ai/consent-anthropic-light.png); [Connect Claude](bring-your-own-ai/connect-claude-light.png);
the [setup step](bring-your-own-ai/setup-connect-step-light.png) and [Use another AI](bring-your-own-ai/use-another-ai-light.png).
At the largest text size the rows first broke words apart; they now stack the action under the name.

## Not run

- No real key, so no live reply, no live tool call, no live photo, no OpenRouter sign-in in a browser.
- Not the full UI suite, and no physical iPhone.
- VoiceOver was not exercised by hand. Rows are combined elements with a selected trait; that is from the code, not from listening.
- Android is unchanged.
