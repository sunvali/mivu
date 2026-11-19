# Update prompts design

Owner-approved on 2026-11-19, with mockups.

## Why

Most iPhones update automatically, but some people stay on old versions. Mivu
needs a calm way to point them at a new version, and a way to stop a version
that is broken or unsafe. Diary data lives only on the phone, so nothing here
may ever lock a person away from their data.

## What ships (iOS first, one PR)

1. **Update card on Today.** When the App Store has a newer version that has
   been released for at least 7 days (so the 7-day phased release still catches
   bugs first), Today shows a small tinted card below the intake card: "Mivu X
   is available", one short line, and an "Update in App Store" button with a
   44-point dismiss control. The card shows once per version. If it is
   dismissed, it comes back once a week later and then stays quiet.
2. **Settings row.** While an update is available, Support shows "Update
   available" with the version number. The row opens the App Store and stays
   until the person updates.
3. **Emergency block.** `https://mivuapp.com/app-config.json` holds
   `{"ios": "x.y.z", "android": "x.y.z"}`. If this app's version is below the
   iOS minimum, a full-screen view covers the app. It has Pip, "Please update
   Mivu", "This version of Mivu needs an update to keep working. Your diary
   stays on this iPhone.", **Update in App Store**, and **Export my diary**
   ("Saves a copy to Files"), which uses the same export as Settings. There is
   no close button. The diary keeps loading underneath so export works. If the
   fetch fails (offline, 404, bad JSON), the app keeps the last minimum it saw
   and is never blocked only because a fetch failed.
4. **What's New.** Highlights for a version are bundled in the app. The first
   launch of a version that has highlights, after an earlier version ran, shows
   a Pip card above the intake card. It has "New in Mivu X", at most three
   one-line highlights and a "Got it" button that marks the card as seen. New
   installs and fix-only versions show nothing.
5. **One thing at a time on Today:** morning check-in, then What's New, then
   the update card. Onboarding and the block are full-screen and sit above
   everything.
6. **Rating:** the existing `RatingPrompt` already asks after a saved meal,
   from the third logged day and once per version. Unchanged.

All new text is localized in every catalog language (en, es, ru, he).

## Checks

- App Store: `https://itunes.apple.com/lookup?id=6826633410` returns `version`
  and `currentVersionReleaseDate`.
- Both checks run at launch and when the app becomes active, at most once an
  hour. They send no personal data or IDs. They are skipped in UI tests and
  sample mode, which use Debug-only fixture flags instead.
- Versions are compared with `String.compare(_:options: .numeric)`.
- State lives in `DiaryLaunch.defaults`.

## Non-goals

- Android. It will use Play in-app updates later.
- Remote messages, feature flags, analytics.
- A Version row in Settings.
- An animated Pip wave on the card. Static Pip art respects Reduce Motion for
  free.
- What's New for the release that ships this feature. Earlier versions never
  recorded which version last ran, so updaters can't be told apart from new
  installs until the next release.

## Operating the minimum

Raise the iOS minimum only after the fixed version is live in every country.
The steps are in `docs/development/app-store-submission.md`. The file lives in
`mivu-site/public/app-config.json` and deploys with the site. The privacy
policy gains one line about the two version checks.
