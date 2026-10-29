# How Mivu uses Sign in with ChatGPT

For App Review (Guideline 5.2.2) and anyone checking how Mivu uses a person's
ChatGPT plan. Code links point to the released source, tag
[`v1.1.3`](https://github.com/sunvali/mivu/tree/v1.1.3) (`8dc3a327`).

## Why no separate approval from OpenAI is needed

OpenAI offers ChatGPT plan usage to open-source apps through a public,
self-service flow. There is no application or client secret.

| OpenAI says | Source |
|---|---|
| "ChatGPT plan usage is available to all open-source partners and selected private clients." | [Quickstart](https://developers.openai.com/siwc/quickstart) |
| "The open-source sign-in flow registers your client and issues OAuth credentials for eligible Responses API requests, without a client secret or partner API key." | [Quickstart](https://developers.openai.com/siwc/quickstart) |
| "These docs explain ChatGPT plan usage for open-source and locally hosted apps. If you're interested in offering it in a paid or remotely hosted app, complete the interest form." | [Overview](https://developers.openai.com/siwc/token-sharing-open-source) |
| "you (a) retain your ownership rights in Input and (b) own the Output." | [Terms of Use](https://openai.com/policies/row-terms-of-use/) |

Mivu matches the open-source, locally hosted case:

- **Open source:** the full source is public at
  [github.com/sunvali/mivu](https://github.com/sunvali/mivu) under the
  [GNU AGPL-3.0](../../LICENSE).
- **Locally hosted:** the app runs on the person's iPhone. Requests go straight
  from the device to `api.openai.com`; Mivu has no server.
- **Not paid:** Mivu is free, with no in-app purchases, subscriptions, ads or
  purchase links.

## Following OpenAI's flow and guidelines

| Requirement | Where Mivu does it |
|---|---|
| First registration through `dynamic_agent_client` with `agent_name_hint=Mivu`, then the issued client ID | [OAuthAttempt.swift:43-56](https://github.com/sunvali/mivu/blob/8dc3a3279b0664a20ff039a0b168bac85384d7f3/ios/Mivu/Connection/OAuthAttempt.swift#L43-L56) |
| Persisted host ID (`ext_agent_host_id`) | [OAuthAttempt.swift:44](https://github.com/sunvali/mivu/blob/8dc3a3279b0664a20ff039a0b168bac85384d7f3/ios/Mivu/Connection/OAuthAttempt.swift#L44) |
| Exactly the documented scopes and `resource=https://api.openai.com/v1` | [OAuthAttempt.swift:47-48](https://github.com/sunvali/mivu/blob/8dc3a3279b0664a20ff039a0b168bac85384d7f3/ios/Mivu/Connection/OAuthAttempt.swift#L47-L48) |
| Use the plan only when `chatgpt.tokens.use.direct` was granted | [Credentials.swift:24](https://github.com/sunvali/mivu/blob/8dc3a3279b0664a20ff039a0b168bac85384d7f3/ios/Mivu/Connection/Credentials.swift#L24) |
| PKCE with S256 | [OAuthAttempt.swift:51-52](https://github.com/sunvali/mivu/blob/8dc3a3279b0664a20ff039a0b168bac85384d7f3/ios/Mivu/Connection/OAuthAttempt.swift#L51-L52) |
| Loopback callback on `127.0.0.1` | [LoopbackCallback.swift:24-36](https://github.com/sunvali/mivu/blob/8dc3a3279b0664a20ff039a0b168bac85384d7f3/ios/Mivu/Connection/LoopbackCallback.swift#L24-L36) |
| Validate state, nonce and the ID token | [AuthSession.swift:41-74](https://github.com/sunvali/mivu/blob/8dc3a3279b0664a20ff039a0b168bac85384d7f3/ios/Mivu/Connection/AuthSession.swift#L41-L74) |
| Protect credentials (Keychain, this device only) | [CredentialStore.swift:30](https://github.com/sunvali/mivu/blob/8dc3a3279b0664a20ff039a0b168bac85384d7f3/ios/Mivu/Connection/CredentialStore.swift#L30) |
| Responses API with `store: false` and `stream: true` | [ResponsesClient.swift:153](https://github.com/sunvali/mivu/blob/8dc3a3279b0664a20ff039a0b168bac85384d7f3/ios/Mivu/Analysis/ResponsesClient.swift#L153) |
| Label the action "Continue with ChatGPT" | [ChatGPTConnectButton.swift:20](https://github.com/sunvali/mivu/blob/8dc3a3279b0664a20ff039a0b168bac85384d7f3/ios/Mivu/Connection/ChatGPTConnectButton.swift#L20) |
| One-time "You're using your ChatGPT plan" notice with "Got it" | [TodayView.swift:203-205](https://github.com/sunvali/mivu/blob/8dc3a3279b0664a20ff039a0b168bac85384d7f3/ios/Mivu/Diary/TodayView.swift#L203-L205) |
| "Using ChatGPT plan" with "Manage usage" near the composer | [CoachView.swift:434-435](https://github.com/sunvali/mivu/blob/8dc3a3279b0664a20ff039a0b168bac85384d7f3/ios/Mivu/Coach/CoachView.swift#L434-L435) |
| "Manage usage" link in Settings | [SettingsView.swift:242](https://github.com/sunvali/mivu/blob/8dc3a3279b0664a20ff039a0b168bac85384d7f3/ios/Mivu/Diary/SettingsView.swift#L242) |
| Usage-limit message points to Manage usage | [ChatGPTConnection.swift:23](https://github.com/sunvali/mivu/blob/8dc3a3279b0664a20ff039a0b168bac85384d7f3/ios/Mivu/Connection/ChatGPTConnection.swift#L23) |

OpenAI's guides: [UI/UX guidelines](https://developers.openai.com/siwc/ui-ux-guidelines),
[registration and sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in),
[preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations).

## Consent and data

Before sign-in, Mivu names OpenAI and the data it sends, and nothing is shared
until the person agrees
([OpenAIConsent.swift:23-27](https://github.com/sunvali/mivu/blob/8dc3a3279b0664a20ff039a0b168bac85384d7f3/ios/Mivu/Connection/OpenAIConsent.swift#L23-L27)).
The same screen says food searches go to USDA FoodData Central only if the
person adds their own USDA key. The diary stays on the iPhone. The person can
disconnect at any time in Settings, and a Coach reply can be reported with
Report Reply.

## Limits we know about

- OpenAI describes this flow as a preview, and its terms may change. We will
  follow any update and change the app if needed.
- Only eligible ChatGPT Plus and Pro accounts can use their plan. Diary features
  work without any account.
