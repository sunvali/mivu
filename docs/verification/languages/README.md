# Language sweep

`MivuUITests/LanguageSweepUITests` opens every main screen and attaches a
capture of each. It runs in one of these modes, chosen by the test runner's
environment:

| `TEST_RUNNER_SWEEP_MODE` | What it launches with | What it proves |
|---|---|---|
| `english` (default) | nothing extra | the screens open; captures for comparison |
| `rtl` | `-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES` | layouts mirror |
| `double` | `-NSDoubleLocalizedStrings YES` | every string goes through localization and long text fits |
| `hebrew`, `spanish`, `russian` | `-AppleLanguages (<code>) -AppleLocale <locale>` | the phone's language reaches every screen (`testPhoneGetsItsLanguage`); Hebrew and Russian screens show no English (`testTextIsTranslated`) |

`TEST_RUNNER_SWEEP_TEXT=largest` adds the largest accessibility text size.

```sh
TEST_RUNNER_SWEEP_MODE=double xcodebuild test -project ios/Mivu.xcodeproj -scheme Mivu -testPlan Mivu \
  -destination 'platform=iOS Simulator,name=iPhone 17' SWIFT_VERSION=6.0 \
  -only-testing:MivuUITests/LanguageSweepUITests
```

In `double` mode the system shows each localized string twice. `testTextIsLocalized`
fails on any label that is not doubled, which is text that never reached a string
catalog. Screens still listed in `notYetLocalized` are skipped by that test.

Captures are attachments named `<mode>-<text>-<screen>` in the result bundle:
`xcrun xcresulttool export attachments --path <bundle>.xcresult --output-path <dir>`.

`baseline/` holds the English captures (default and largest text, iPhone 17,
downscaled) taken at commit `3824a898` before any language change, with the
status bar fixed by `xcrun simctl status_bar <device> override --time 9:41`.
Pip and the keyboard animate, so compare layout, not pixels.

The meal composer and manual entry are reached in sample mode; with Coach enabled,
**Log meal** opens the chat instead.
