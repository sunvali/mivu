# Mivu

Mivu is a private food diary for iPhone with a friendly coach. Log meals in your
own words, by photo or by voice, and review every estimate. Your diary and photos
stay on your iPhone; there is no Mivu account or server.

This repository holds the source of the iPhone app as released on the App Store.
It is published from each release tag.

## AI that uses your own plan

Coach and meal analysis use the person's own ChatGPT plan through OpenAI's
[Sign in with ChatGPT](https://developers.openai.com/siwc/token-sharing-open-source)
for open-source apps. Mivu asks before anything is shared with OpenAI, keeps the
sign-in token in the iOS Keychain, and works without ChatGPT for logging, history,
progress and backup. On supported iPhones, Apple Intelligence can log meals
on-device instead.

## Build

1. Xcode 27 or later (the app runs on iOS 26 and uses iOS 27 APIs when available).
2. Open `ios/Mivu.xcodeproj` and choose the `Mivu` scheme.
3. Set your own signing team and bundle identifiers to run on a device.

## License

The code is licensed under the [GNU AGPL v3.0](LICENSE). The Mivu name, icon and
the Pip character artwork are not; see [NOTICE.md](NOTICE.md). Pull requests are
not accepted at this time. Questions: https://mivuapp.com/support.
