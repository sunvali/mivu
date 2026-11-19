# Send feedback

Plan: [2026-11-19-send-feedback.md](../superpowers/plans/2026-11-19-send-feedback.md).
Spec: [2026-11-19-send-feedback-design.md](../superpowers/specs/2026-11-19-send-feedback-design.md) (see its Amendments).
Branch `feat/send-feedback`, from `main` at `0fcceeee`.

## What changed

- Settings › Support has a **Send feedback** row. It opens a form: Bug, Idea or
  Question; a message; an optional email (shown only when the app sends the report itself); and the app version, iOS version,
  device model and language that are sent, shown before sending. Diary data is
  never added.
- A Coach message that failed and needs a retry offers **Report this problem**,
  which opens the same form with Bug selected and a short error code
  (`coach_network`, `coach_session` or `coach_other`) in the list.
- Coach is told to offer the Settings link and name the Send feedback row when
  someone wants to report a bug, suggest a feature or contact the team, and
  never to say a report was sent.
- Delivery: `MIVU_FEEDBACK_ENDPOINT` is empty in this change, so the button
  reads "Send by email" and opens a prefilled email to support@mivuapp.com.
  When no mail app opens, the screen shows the address with Copy address. With
  an endpoint set, the form posts JSON and treats only HTTP 204 as sent; on
  failure it keeps the text and offers Try Again and Send by email instead.
- New text has English, Spanish, Russian and Hebrew in the string catalog.
- Server side (separate repo `mivu-infra`, branch `feat/feedback-route`):
  the existing reports worker accepts `POST /feedback` and emails the report
  with the person's address as Reply-To.

## Evidence

- Tested source: `be84e011e2b888ee32ebf09aa15eb8c5749f9a4b`, rebased on `main` at `05ab4866` (1.8.0). This
  record's own commit changes docs only.
- Environment: macOS 27.0, Xcode via the `xcodebuildmcp` CLI, scheme `Mivu`,
  test plan `Mivu`, simulator "Mivu send-feedback" (iPhone 17 Pro, iOS 27.0).
- `MivuTests/FeedbackTests`, `MivuTests/FeedbackFormTests`,
  `MivuTests/CoachContextMessagesTests`, `MivuUITests/FeedbackUITests`:
  32 passed, 0 failed.
- Before the rebase, with the Coach change in place, `CoachManualEngineTests`,
  `ArchiveFixtureTests`, `CoachToolsFixtureTests` and `CoachFocusTests` ran
  with the feedback suites: 49 of 50 passed. The one failure was
  `CoachFocusTests/lastChangedIsMostRecentMealToday`, a date expectation
  (2027-01-15 against 2027-01-14) in code this branch does not touch. It was
  not rerun and is not counted as passing.
- Worker: `node --import ./reports/test-setup.mjs --test reports/worker.test.mjs`
  in `mivu-infra` at `7a83b9d`: 5 passed, 0 failed.
- Failed first: the Task 1 model tests and the Coach rule test (compile
  failures), and the worker tests (204 where 400 was expected). The form tests
  and the tests added with the QA and review fixes were written together with
  their code and were not seen to fail first.
- A QA pass on the simulator, a design review of the screenshots and an
  independent code review ran before the last two commits. Fixed from them:
  Send hidden by the keyboard and no way to dismiss it, the Coach error line
  missing from the list, a lost draft, no hint for an invalid email, the
  button drawn as a table row, a reply address asked for on the email path
  that could not carry it, no VoiceOver announcement of the result, and a
  second mail draft on a double tap.
- Screenshots: [feedback/](feedback/). They are from the build one commit
  before the tested source. Since then the email field is hidden while reports
  go through the mail app, so `form-filled-light`, `form-keyboard`,
  `form-empty-light`, `form-dark` and `form-mail-unavailable` show a field the
  current build shows only with direct sending. `settings-row` is from an
  earlier build; the row did not change.

## Not passing or not run

- Direct sending has never reached the live worker: the route is not applied
  and no endpoint is configured. The network path is tested against a stub.
- Whether Cloudflare's email binding accepts the Reply-To header is untested
  until the route is applied.
- Whether Coach follows the new rule was not checked with a live model.
- Not run: a physical iPhone, VoiceOver by hand, the Spanish and Russian
  layouts on the final build, the "Report this problem" sheet on the final
  build (it was exercised on the build before the last commit), the full unit
  and UI suites.
- The privacy manifest, privacy policy and App Store privacy label are
  unchanged, because nothing is collected by the app until direct sending is
  switched on. They change in that later step.
