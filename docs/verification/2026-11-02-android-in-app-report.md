# Android in-app Coach reply report verification

Recorded 2026-11-02. Why: Google Play's AI-generated content policy (read live 2026-11-02) requires apps to let users
report offensive AI output "to developers without needing to exit the app". The earlier flow saved the report on the
phone and opened an email draft, which leaves the app.

- Tested source: `53d69bd08bede27035ff0cbf8887cc6cd9c1b5f6` on branch `fix/coach-report-in-app`, from `main` at
  `72e05279`. The instrumented run used the same Android sources before the commit; only docs changed after it.
- Environment: macOS 27.0, Android Studio JBR, Gradle via `./gradlew`; emulator-5554 (`Medium_Phone_API_37.0`, API 37).
- Commands: `./gradlew :app:testDebugUnitTest :app:lintDebug`, and `:app:connectedDebugAndroidTest` with
  `-Pandroid.testInstrumentationRunnerArguments.class=com.yakov103.mivu.ui.coach.CoachReplyActionsTest`. No full connected
  suite was run.
- Counting rule: counts are from the task runs (the JUnit and instrumented XML result files).

## Results

| Scope | Result |
|---|---|
| JVM `:app:testDebugUnitTest` (includes `CoachReportsTest.sendPostsOnlyTheReportAndReadsTheStatus`, new) | 398 passed, 0 failed |
| `:app:lintDebug` | build successful |
| `CoachReplyActionsTest` (new: `reportSavesAndSendsWithoutLeavingTheApp`; `reportFallsBackToEmailWhenItCannotBeSent` replaces `reportSavesThenOpensEmail`) | 15/15 |

## Failed first

- `CoachReportsTest.sendPostsOnlyTheReportAndReadsTheStatus` failed to compile before the change (no `CoachReports.body`
  or `send`). The instrumented cases were updated with the code and not seen to fail first.

## Not passing or not run

- The live endpoint `https://reports.mivuapp.com/` does not exist until the owner applies the mivu-infra worker, so no
  report has reached an inbox. The dialog tests stub the send; the JVM test posts to a local server.
- Not run: a physical phone, TalkBack by hand, offline behavior on a device, a release build.
