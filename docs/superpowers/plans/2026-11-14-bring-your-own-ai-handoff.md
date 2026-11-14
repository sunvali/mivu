# Bring your own AI — handoff

Written 2026-11-14 for whoever picks this up next. It records what the code, the design and the test record do not:
the state the work was left in, the decisions made while building, the App Store findings, and how to resume.

## State

- **Parked by the owner on 2026-11-14.** Do not merge or submit without being asked.
- Draft pull request: [sunvali/mivu#126](https://github.com/sunvali/mivu/pull/126), branch `feat/bring-your-own-ai`,
  twelve commits on `main` at `90664b9a`. Last code commit `77b8f6f1`.
- iOS only. Android is not started.
- **No request with a real key has reached any service.** Every service is "built, not verified live".
- The owner has a Claude Max plan. It gives no API key. Claude testing needs a Claude Console key with prepaid
  credit; Gemini needs only a free Google AI Studio key.

## Where things are

| What | Where |
|---|---|
| Design the owner approved | `docs/superpowers/specs/2026-11-14-bring-your-own-ai-design.md` |
| Mockup the owner approved | `docs/superpowers/specs/assets/2026-11-14-bring-your-own-ai-mockup.png`, source `…-mockup.html` beside it |
| Build plan, all eight tasks done | `docs/superpowers/plans/2026-11-14-bring-your-own-ai.md` |
| Test record and screenshots | `docs/verification/2026-11-14-bring-your-own-ai.md`, `docs/verification/bring-your-own-ai/` |
| Parity row | `docs/parity.md`, id `byo-ai` |
| Services, links, default models, Keychain store | `ios/Mivu/Connection/KeyService.swift` |
| Claude request and reply translation | `ios/Mivu/Analysis/MessagesWire.swift` |
| Gemini and OpenRouter translation | `ios/Mivu/Analysis/ChatCompletionsWire.swift` |
| HTTP, status mapping, model lists | `ios/Mivu/Analysis/KeyServiceClient.swift` |
| Choosing a service, saving a key, binding a reply | `ios/Mivu/Connection/ChatGPTConnection.swift`, section `// MARK: Key services` |
| OpenRouter sign-in | `ios/Mivu/Connection/OpenRouterSignIn.swift` |
| Screens | `ios/Mivu/Connection/KeyServiceViews.swift`, `SettingsView.swift` (`.connection` case), `OnboardingView.swift` (connect step) |
| Tests | `ios/MivuTests/KeyService*Tests.swift`, `KeyConnectionTests.swift`, `OpenRouterSignInTests.swift`; UI in `CoachUITests` and `DiaryUITests` |

## What the owner decided

Four services at launch (Claude, OpenAI, Gemini, OpenRouter). One active AI, picked in Settings. A quiet "Use another
AI" link in setup. Paste for three services, a sign-in button for OpenRouter. Mivu picks a cheap default model and the
person can change it. One cost notice when connecting. A separate consent prompt per service, like ChatGPT's. iPhone
first, Android after. Build first and test with real keys later.

## Decisions made while building

Each is the builder's call, not the owner's. The cost of being wrong is given so it can be revisited.

1. **Requests are not streamed.** Coach never shows partial text. Cost: a reply slower than 180 s fails. Marked
   `shortcut:` in `KeyServiceClient.swift`.
2. **Default models**, looked up 2026-11-14: `claude-haiku-5-5`, `gpt-6-luna`, `gemini-3.5-flash-lite`, and
   `anthropic/claude-haiku-5.5` on OpenRouter. The owner chose "cheap"; estimates may be weaker than a larger model's.
3. **OpenRouter's picker is a fixed list of six models**, not its catalogue of several hundred.
4. **Gemini lists ids as `models/<id>`**; the client strips the prefix.
5. **The key check lists models** instead of sending a paid test message. It proves the key is valid, not that the
   account has credit.
6. **Key logic lives in `ChatGPTConnection.swift`**, not a separate file, because it uses that file's private state.
7. **Saved keys are read in `init`**, so the active AI is right from the first frame.
8. **A reply is bound to key, provider and model.** Key changes move `keyRevision`, kept apart from `generation`,
   which guards ChatGPT sign-in. Today restarts a reply when the provider or model changes.
9. **Gemini answers a wrong key with HTTP 400** (seen live). The key check treats that as "rejected". A chat request
   keeps 400 as a plain failure. Cost: a Gemini key revoked later shows "couldn't finish", not "replace key".
10. **A reply of HTTP 404 reloads the model list** and picks a listed model, so a retired model heals itself.
11. **With no key service active, wording still says "Connect ChatGPT"**, because ChatGPT is the recommended path and
    five UI tests quote that string.
12. **An empty Claude balance is assumed to arrive as HTTP 402** (Anthropic's error table). The reviewer expected 400.
    Not verified.
13. **A cancelled OpenRouter sign-in** could in theory still save the key if Cancel lands in the instant the key check
    returns. It could not be reproduced in a test, so no code was added.
14. **`testSetupOffersAnotherAIBesideChatGPT` was written after the link existed** and was never seen failing.

## Known failing test, not from this branch

`CoachToolsFixtureTests/fixturesMatchCurrentDeclarationsAndFingerprints` fails with "tools.json is stale". It compares
`CoachTools.declarations()` with `fixtures/coach/tools.json`. This branch changes neither. It was not re-run on `main`
to confirm. Check it on `main` before blaming a rebase.

## Open items, in the order to do them

1. **Rebase on `main`.**
2. **Live-test each service with a real key**, one photo meal each. First checks:
   - Claude: tool schema accepted; thinking blocks accepted when sent back; what an empty balance returns.
   - OpenAI: whether a plain key accepts the `namespace` tool form. If not, send a flat function list.
   - Gemini: whether the tool schema (nullable type arrays, `additionalProperties`) is accepted. If not, rewrite the
     schema for Gemini inside `ChatCompletionsWire`; do not fork `CoachTools`.
   - OpenRouter: whether sign-in returns to `http://127.0.0.1:<port>/auth/callback`. If not, make it a pasted key.
   Ask for keys through a secret prompt, never in chat. Never commit, log or screenshot a real key.
3. **Minor review findings**, all deferred:
   - "Test and save" shows only a spinner while checking, with no VoiceOver label.
   - The key error message appears without a VoiceOver announcement.
   - A key over 512 bytes gets the "without spaces" message.
   - Failure wording names the provider active when the message is built.
   - `removeKey` leaves a `keyRejected` or `keyQuota` notice that a later ChatGPT screen can show.
   - After a reinstall the Keychain key survives but consent does not, so the person pastes again.
   - `restore()` waits on the key service's model list before ChatGPT restore starts.
   - Leftovers: `KeyConnectionError.consentRequired` has no UI branch; `Provider` is `CaseIterable` without a user;
     `chosenModels` mirrors a preference.
4. **App Store changes**, below.
5. **Android**, from the same spec, as its own plan and pull request.

## App Store findings

Checked against Apple's review guidelines on 2026-11-14. The page's last tenth was not read. This is a reading of the
text, not a prediction of a reviewer. Version 1.2.0 was still waiting for review that day; this work is not in it.

| Risk | Guideline | What to do before submitting a build that contains this |
|---|---|---|
| "Get a key" opens a page where people buy credit. Outside the US storefront, apps "may not include buttons, external links, or other calls to action that direct customers to purchasing mechanisms other than in-app purchase". The same guideline bans "license keys" that unlock functionality. | 3.1.1 | Replace the "Get a key" link and the key-service "Manage usage" link with plain text. The review notes say "no purchase links"; keep that true or change the notes. |
| Reviewers cannot test without credentials. | 2.1 | Give one working key in the review notes (a free Gemini key is enough) and a short demo video. |
| The policy and privacy answers name only OpenAI. | 5.1.1, 5.1.2 | Name Anthropic, Google and OpenRouter in the privacy policy, the App Privacy answers and the review notes. The per-service consent prompt already meets 5.1.2(i). |
| Apple may ask for proof of permission to use the services. | 5.2.2 | Lower risk than the ChatGPT plan flow: public APIs with the person's own key. |
| China. | 5 | No new exposure while mainland China, Hong Kong and Macau stay removed. Do not add "Claude" or "Gemini" to listing text or keywords. |
| Mivu's minimum age is 13; Google's and Anthropic's API terms are for adults, as far as known. Android already limits Gemini Nano to 18+. | terms, not Apple | Decide whether key services are hidden for under-18 profiles. |

Recommendation given to the owner: keep this out of any submission until 1.2.0 is approved and released.

## How to run the tests

The simulator used here was deleted afterwards. Make a new one on iOS 27.0; iPhone 17 is not offered on the 27.1 runtime.

```sh
SIM=$(xcrun simctl create "Mivu BYO AI" com.apple.CoreSimulator.SimDeviceType.iPhone-17 com.apple.CoreSimulator.SimRuntime.iOS-27-0)
xcodebuildmcp simulator test --project-path "$PWD/ios/Mivu.xcodeproj" --scheme Mivu --simulator-id "$SIM" \
  --derived-data-path "$PWD/build/byo/DerivedData" --output json \
  --json '{"extraArgs":["-testPlan","Mivu","-parallel-testing-enabled","NO","-only-testing:MivuTests/KeyConnectionTests"]}'
```

- Unit suites for this feature: `KeyServiceTests`, `KeyServiceWireTests`, `KeyServiceClientTests`,
  `KeyConnectionTests`, `OpenRouterSignInTests`. Neighbours worth re-running: `CoachConnectionTests`,
  `ConnectionTests`, `SessionTests`, `ResponsesClientTests`.
- UI tests on the changed screens: `CoachUITests/testCoachAISettingsOffersKeyServicesAndAsksConsentFirst`,
  `testChatGPTConnectAsksForSharingConsentFromCoachAndSettings`,
  `testOfflineTextPhotoCapturePersistsAcrossRelaunchAndTabs`, and `DiaryUITests/testSetupOffersAnotherAIBesideChatGPT`,
  `testFirstRunOpensSetupWithoutInventingRecords`, `testLegacyHebrewLaunchUsesEnglishLeftToRight`.
- Read failures from the result bundle: `xcrun xcresulttool get test-results summary --path <bundle>`.
- UI tests assume the default text size. A simulator left at an accessibility size pushes rows off screen and fails them.
- To see a screen by hand, launch with `--diary-ui-test <uuid> --coach-ui-test --proof-english`. Setup needs
  `--onboarding-ui-test` instead of `--coach-ui-test`.
- Pushing runs a hook that needs Java:
  `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME=$HOME/Library/Android/sdk git push`.
- The wrong-key probe that found the Gemini 400 is in the test record. It uses a made-up key and no personal data.
