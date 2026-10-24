# Android Phase 0 verification

Recorded 2026-10-23. Spec: [Phase 0: ChatGPT proof](../superpowers/specs/2026-10-23-android-app-design.md#phase-0-chatgpt-proof-release-gate).
Proof screen: `android/app/src/debug/java/com/yakov103/mivu/ConnectionProofActivity.kt` (debug builds only; absent from the release APK and merged manifest).
Source SHA of the proof screen: `f019413e95d0ee24950f642a44b9baa7a941cf5b`.

Exit rule: items 2 to 5 pass on the physical phone, and items 1 and 6 have a
written answer. Otherwise the release stays blocked.

Local checks at that SHA (Medium_Phone_API_37.0 emulator): the proof-screen
instrumented test (2 tests: six labelled buttons at least 48 dp; "Sign in" opens
`https://auth.openai.com/api/accounts/authorize` with a `127.0.0.1` redirect)
passed, 50 unit tests passed, `:app:assembleRelease` succeeded. These are not
live-provider evidence.

## 1. Eligibility (external)

- Environment: not applicable (written answer from OpenAI).
- Source SHA: n/a
- Steps: none yet. Ask OpenAI in writing whether a Play-distributed, closed-source Mivu may use this flow (same question applies to iOS).
- Result: **blocked** (awaiting a written answer)
- Notes: the [quickstart](https://developers.openai.com/siwc/quickstart) says ChatGPT plan usage is "available to all open-source partners and selected private clients"; paid or remotely hosted apps are pointed to an interest form ([overview](https://developers.openai.com/siwc/token-sharing-open-source)). The docs say nothing about closed-source apps distributed through app stores.

## 2. Authentication

- Environment: emulator Medium_Phone_API_37.0, then physical phone (model and Android version to record).
- Source SHA: f019413e95d0ee24950f642a44b9baa7a941cf5b
- Steps: tap Sign in; complete sign-in in the Custom Tab with the app backgrounded. After the "You can return to Mivu." page, press Back to return to the app, then read the Sign in line; confirm PASS; kill the process and sign in again. Contract: [sign-in docs](https://developers.openai.com/siwc/token-sharing-open-source/sign-in).
- Result: **partial — emulator PASS; physical phone not run**
- Notes: to prove: loopback redirect `http://127.0.0.1:<port>/auth/callback` reaches the listener from a Custom Tab on a real phone, including while backgrounded; listener starts before the browser opens; PKCE S256, `state`, `nonce`; `dynamic_agent_client` plus `agent_name_hint=Mivu` only on first registration; `ext_agent_host_id` persisted before sign-in. Emulator run 2026-10-24 at `ef06a98823460e6762dde1112789b3be7eb304d5` (Medium_Phone_API_37.0, API 37, emulator started with `-dns-server 8.8.8.8,1.1.1.1`). The owner was already signed in to ChatGPT in the emulator browser, chose the account, named the agent `mivu-android-simulator` and tapped Continue on the consent screen; the loopback redirect reached the app and the screen read `PASS: Signed in`. The consent page kept its spinner; closing the Custom Tab showed the result. The kill-and-sign-in-again step was not run. Earlier attempts failed with `NetworkUnavailable` because the emulator's default DNS could not resolve `auth.openai.com` (`UnknownHostException`); the Custom Tab still worked because Chrome resolves names itself.

## 3. Authorized inference

- Environment: as item 2.
- Source SHA: f019413e95d0ee24950f642a44b9baa7a941cf5b
- Steps: after sign-in, tap List models, then Analyze text.
- Result: **partial — emulator PASS; physical phone not run**
- Notes: one Responses request with `store: false`, `stream: true`, unsupported fields omitted ([limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)). Emulator run 2026-10-24 at `ef06a98823460e6762dde1112789b3be7eb304d5` (Medium_Phone_API_37.0, API 37, emulator started with `-dns-server 8.8.8.8,1.1.1.1`). List models: `PASS: 7 models; first: gpt-6.1-sol`. Analyze text returned a model reply. A Coach turn through the new Coach engine (debug "Run Coach turn", synthetic text) read `PASS: Turn completed; 1 saved records`.

## 4. Real analysis

- Environment: as item 2.
- Source SHA: f019413e95d0ee24950f642a44b9baa7a941cf5b
- Steps: Analyze text ("two boiled eggs and a slice of toast"); Analyze photo with a test meal photo (not personal diary data).
- Result: **partial — text PASS on emulator; photo and physical phone not run**
- Notes: the proof screen shows the analysis text, not a diary entry; the diary-entry part of this item needs the later analysis work. The first catalog model is used, as on iOS; image input works only "when the selected model accepts them". Emulator run 2026-10-24 at `ef06a98823460e6762dde1112789b3be7eb304d5` (Medium_Phone_API_37.0, API 37, emulator started with `-dns-server 8.8.8.8,1.1.1.1`). Analyze text with the synthetic "two boiled eggs and a slice of toast" returned a calorie estimate from `gpt-6.1-sol`. Analyze photo was not run.

## 5. Token refresh

- Environment: as item 2.
- Source SHA: f019413e95d0ee24950f642a44b9baa7a941cf5b
- Steps: tap Force refresh (passes only if the access token changed); tap Disconnect. Reference: [errors](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery).
- Result: **partial — refresh PASS on emulator; Disconnect and physical phone not run**
- Notes: refresh must replace access token, expiry, scopes and rotating refresh token together; `invalid_grant` / `refresh_token_reused` clear tokens, a temporary network failure never does. The invalid-grant and network paths are covered by unit tests only, not live. Emulator run 2026-10-24 at `ef06a98823460e6762dde1112789b3be7eb304d5` (Medium_Phone_API_37.0, API 37, emulator started with `-dns-server 8.8.8.8,1.1.1.1`). Force refresh read `PASS: Refreshed; the new token replaced the old one`. Disconnect was skipped at the owner's request.

## 6. Reviewer access path

- Environment: not applicable (Play Console and a reviewer ChatGPT account).
- Source SHA: n/a
- Steps: none yet. Show a dedicated reviewer account can sign in and analyze without a one-time code the reviewer cannot receive, or document the path Play accepts.
- Result: **blocked** (awaiting a written answer and the owner's authorization for a paid reviewer account)
- Notes: Play requires sign-in details that work at all times and from any location, plus step-by-step instructions for third-party sign-in ([Google](https://support.google.com/googleplay/android-developer/answer/15748846)). Whether the account needs email codes, and whether OpenAI's terms allow it, are unverified.
