# Test Mivu on your iPhone with your ChatGPT plan

This guide is for the owner to use after the current core build is declared ready. It describes a personal, local Xcode install and real-account test; it does not say that signing, provider connection, or iPhone acceptance has already succeeded. The current Mivu project uses `ios/Mivu.xcodeproj`, the `Mivu` scheme, and iOS 26 as its minimum. No development team is committed to the project.

## Install from Xcode

1. Open `ios/Mivu.xcodeproj` in Xcode and sign in to your Apple Account in Xcode’s account settings.
2. Connect and unlock your iPhone, choose the `Mivu` scheme, and select that device as the run destination. In the app target’s Signing & Capabilities settings, enable **Automatically manage signing** and select your **Personal Team**. Keep the team selection local; do not commit a development-team identifier.
3. If Xcode or iOS asks, trust the Mac and enable Developer Mode on the iPhone yourself. Follow the on-device restart and confirmation prompts. Complete any required account or agreement steps yourself; Personal Team testing does not require purchasing membership.
4. Press Run in Xcode. Check that the app opens on the phone and that the installed build is the intended core build. A release ZIP or unsigned archive is not an iPhone installation package.

Apple allows personal-device development signing with an Apple Account and Personal Team in Xcode. Its personal provisioning profiles expire after seven days; after expiry, rebuild and reinstall from Xcode. See [Apple’s developer-account overview](https://developer.apple.com/help/account/basics/about-your-developer-account/) and [Xcode’s device-running guide](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices). Enabling Developer Mode and trusting the computer are actions you perform on your own device; see [Enable Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

## Connect your ChatGPT plan

In Mivu Settings, use the visible ChatGPT connection and plan-permission action when it is available. Sign in with the ChatGPT account you intend to test with, review the account and plan permissions, and grant plan use only if you choose to. The app must confirm that plan permission is active before making a real request. No API key is needed for the documented open-source Sign in with ChatGPT flow, and Mivu must not switch to paid API billing when plan use is unavailable.

OpenAI documents ChatGPT plan usage for eligible Plus and Pro accounts in participating open-source apps. Eligibility and permission are checked during the real account flow; the plan name alone does not guarantee access. The permission covers eligible app inference, not ChatGPT conversations. Usage draws on your existing plan allowance, which you can review and control in ChatGPT Settings → Usage. If permission is declined or the service is temporarily unavailable, stop the live test and follow the displayed recovery guidance; do not enter an API key as a workaround. Read OpenAI’s [open-source plan-usage guide](https://developers.openai.com/siwc/token-sharing-open-source), [sign-in and permission steps](https://developers.openai.com/siwc/token-sharing-open-source/sign-in), [models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference), [errors and recovery](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery), and [preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations).

## Owner acceptance checklist

Run these checks on the ready build and record the app revision, phone/iOS version, result, and any blocked step. Launch the ordinary app, not a UI-test fixture or the explicit `--sample-mode` path, which produces synthetic data. These live checks are currently unverified; prior simulator tests used synthetic inputs.

- [ ] Install and launch the intended core build from Xcode on the iPhone.
- [ ] Complete the real ChatGPT sign-in and explicitly verify that plan use is permitted before sending a request.
- [ ] Send a text meal and confirm that Mivu saves and displays the resulting diary record.
- [ ] Capture a real meal photo and confirm the saved result can be corrected; do not include credentials or unrelated personal details in logs or screenshots.
- [ ] Correct a meal and ask about yesterday’s food; confirm the displayed day and totals match saved records.
- [ ] Record a morning weight and a workout. Confirm estimated workout burn stays separate from food intake and the actual daily budget.
- [ ] Review a weekly report with sparse or missing days. Confirm missing data is not presented as zero or as a complete average.
- [ ] Relaunch the app and confirm saved records remain. Exercise offline capture and retry without creating duplicates.
- [ ] Optional: test Files backup export and restore using a separate backup copy. Do not restore over the only copy of current data or start a fresh restore without an isolated backup.

## What this does not establish

The current native evidence is from synthetic simulator and SQLite tests. The Sign in with ChatGPT flow, account eligibility, native iPhone callback/loopback behavior, live text or image recognition, physical-device accessibility, and actual Files-provider roundtrip have not been verified on an iPhone. The OpenAI flow can be restricted by account, region, consent, usage, or temporary service availability; successful simulator tests do not guarantee that every account or phone will pass these live checks. Report each result as observed, blocked, or not run.
