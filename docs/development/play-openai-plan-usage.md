# How Mivu for Android uses Sign in with ChatGPT

For Google Play review and anyone checking how the Android app uses a person's
ChatGPT plan. The iPhone app has [its own page](../app-store/openai-plan-usage.md);
this one stands alone so neither depends on the other. Paths are under
`android/app/src/main/java/com/yakov103/mivu/`. Before submission, link them to
the `android-v` tag of the uploaded build.

## Why no separate approval from OpenAI is needed

OpenAI offers ChatGPT plan usage to open-source apps through a public,
self-service flow, with no application or client secret: "ChatGPT plan usage is
available to all open-source partners and selected private clients"
([quickstart](https://developers.openai.com/siwc/quickstart)). Paid or remotely
hosted apps are sent to an interest form
([overview](https://developers.openai.com/siwc/token-sharing-open-source)).

Mivu for Android matches the open-source, locally hosted case:

- **Open source:** the full source is public at
  [github.com/sunvali/mivu](https://github.com/sunvali/mivu) under the
  [GNU AGPL-3.0](../../LICENSE).
- **Locally hosted:** the app runs on the person's phone. Sign-in goes to
  `auth.openai.com` and requests go straight from the phone to `api.openai.com`
  with the person's own token. Mivu has no server in that path.
- **Not paid:** free, with no in-app purchases, subscriptions or ads.

The only Mivu service the app talks to is `reports.mivuapp.com`. It receives a
Coach reply the person chooses to report (the reply text, reason, note and app
version) and emails it to the developer; it stores nothing and never sees the
ChatGPT token or the diary (`ui/coach/CoachReport.kt:95`).

## Following OpenAI's flow

| Requirement | Where |
|---|---|
| First registration through `dynamic_agent_client` with `agent_name_hint=Mivu`, then the issued client ID | `connection/OAuthAttempt.kt:22`, `:82`, `:93` |
| Persisted host ID (`ext_agent_host_id`) | `connection/OAuthAttempt.kt:83` |
| The documented scopes and `resource=https://api.openai.com/v1` | `connection/OAuthAttempt.kt:86-87` |
| Use the plan only when `chatgpt.tokens.use.direct` was granted | `connection/Credentials.kt:39` |
| PKCE with S256, `state` and `nonce` | `connection/OAuthAttempt.kt:79-90` |
| Loopback callback on `127.0.0.1` | `connection/LoopbackCallback.kt:17` |
| Credentials encrypted with the Android Keystore, outside backups | `connection/CredentialStore.kt:24`, `:108` |
| Responses API with `store: false` and `stream: true` | `analysis/ResponsesClient.kt:78` |
| One-time "You're using your ChatGPT plan" notice | `ui/today/TodayScreen.kt:176` |
| "Using ChatGPT plan" with "Manage usage" near the composer | `ui/coach/CoachComposer.kt:450-453` |
| "Manage usage" in Settings | `ui/settings/SettingsScreen.kt:204` |

## Consent and data

Before sign-in the app shows "Share with OpenAI?", names the data it sends, and
opens sign-in only after "Agree and Continue"
(`ui/settings/ChatGPTConnectButton.kt`). The diary stays on the phone, and the
person can disconnect in Settings › Coach AI. The policy is at
<https://mivuapp.com/privacy/android>.

## Limits we know about

- OpenAI describes this flow as a preview, and its terms may change.
- This is the developer's reading of OpenAI's public documents, not a written
  answer from OpenAI.
- Only eligible ChatGPT accounts can use their plan. The diary works without
  any account.
