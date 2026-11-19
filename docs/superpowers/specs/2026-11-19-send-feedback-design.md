# Send feedback: design

Date: 2026-11-19. Base: `origin/main` at `0fcceeee`. Status: approved by the owner, amended the same day (see Amendments).

## Why

People who hit a bug or want a feature have no way to tell us from inside Mivu.
The only report path is "Report Reply" on a Coach answer, which opens an email.
The owner wants a proper feedback screen that sends directly from the app, so a
person never leaves Mivu and every report arrives with the details needed to act
on it.

## Goals

- One native screen to send a bug, an idea or a question.
- Sent directly from the app; no mail app needed on the normal path.
- Every report carries app version and build, iOS version, device model and app
  language, and the person sees that list before sending.
- The owner reads reports in the existing `support@mivuapp.com` inbox and can
  reply when the person left an email.
- Nobody loses text they wrote because sending failed.

## Non-goals

Screenshots or attachments, shake to report, a public roadmap or voting,
in-app replies or a ticket history, device attestation, Android (follows in its
own PR with its own copy of everything; Android never reads `ios/`).

## Anti-goals

- Diary data (meals, photos, weights, workouts, goals, profile, chat) in a
  report. The app never adds it, in any path.
- A report that includes anything the screen did not show the person.
- A silent failure: the screen says "sent" only after the server accepted it.
- Any copy promising the app is free forever or has no purchases.

## What the owner decided

1. **Delivery:** directly from the app to a Lambda in the Mivu AWS account
   (582169340364), which forwards the report by email to `support@mivuapp.com`,
   with the person's email as reply-to when given.
2. **Screen:** a native form. Type picker (Bug, Idea, Question), a message
   field, an optional email field, a visible "Included with your report" list,
   and Send.
3. **Diagnostics:** app version and build, iOS version, device model, app
   language. Shown to the person. Nothing else.
4. **Entry points:** a "Send feedback" row in Settings beside Privacy Policy and
   Rate Mivu; a "Report this problem" action on a Coach turn that failed and
   offers "Try again"; and a link from Coach when someone asks to report a bug
   or suggest a feature.
5. **Email field:** optional.
6. **When sending fails:** keep the text, show a short error, offer Try Again
   and "Send by email instead", which opens the same report as a prefilled
   email to `support@mivuapp.com`.
7. **AWS:** the owner will unblock Lambda in the organization policy.

## Blocked until the owner acts

An organization service control policy (`p-il73h2vb`, parent account
070443470992) explicitly denies Lambda and SES in the Mivu account; observed on
2026-11-19 in us-east-1 and eu-west-1. Do not work around it. Needed from the
owner before the server part can be deployed:

- Lambda allowed in one region.
- SES allowed in the same region, and `mivuapp.com` verified for sending (DNS
  records). Sending only from and to `mivuapp.com` addresses works inside the
  SES sandbox, so no production-access request is needed.

**Owner decision for the meantime:** the screen ships now. While no endpoint is
configured in the app, Send opens the prefilled email instead (the same path as
"Send by email instead"), and the screen makes no claim that anything was sent
directly. Once the function is deployed and verified, one configuration value
switches Send to the direct path. The app must never ship pointing at an
endpoint that does not exist.

## Builder's calls (not owner decisions; the owner saw this list)

- **Languages:** English, Spanish and Russian in `Localizable.xcstrings`.
- **Server:** one small function behind a Lambda function URL, code in a new
  `server/feedback/` folder in this repo, deployed by hand with the `mivu` AWS
  profile (check `aws sts get-caller-identity` first). No framework.
- **Request:** JSON with exactly `kind` (bug, idea, question), `message`,
  optional `email`, `appVersion`, `build`, `os`, `device`, `language`, and
  optional `context` (a short fixed code such as a Coach failure reason, never
  free text from the diary). Unknown fields, a missing message, a message over
  4,000 characters or a malformed email are rejected.
- **Abuse limits:** the size cap above, a low reserved concurrency on the
  function, and the user's text is placed only in the email body, never in
  headers. The reply-to is set only from a validated address. Upgrade to App
  Attest if spam appears.
- **Email subject:** `[Bug] Mivu 1.7.0 (123), iOS 26.1` style, so the inbox
  sorts itself.
- **After a successful send:** a brief thank-you, then the screen closes.
- **Coach failure entry:** opens the same screen with Bug selected and the
  failure reason code in `context`. It never prefills the person's message or
  the Coach conversation.
- **Coach link entry:** reuse the existing Coach-to-Settings handoff (the
  `coachSettingsLink` path and `CoachDestination`), adding a feedback
  destination. It needs a tap; Coach never sends a report itself.
- **`context` values:** a closed set of codes mapped in the app (for example
  `coach_network`, `coach_session`, `coach_other`), never the raw
  `CoachEngine.failureReason` string. When present it appears in the
  "Included with your report" list, and the server accepts only that set.
- **`language`:** the app's selected language code, not the device locale.
- **Duplicates:** a retry after a lost response may deliver a report twice.
  Accepted; no idempotency key, since the server stores nothing.
- **Email fallback body:** type, message and the same diagnostics list. The
  email field is left out because the person's mail app supplies the sender.
- **Coach handoff touch points on main:** `CoachDestination`
  (`CoachModels.swift:7`), the `open_settings` tool schema
  (`CoachManualEdits.swift:86`), `linkTitle`, and `SettingsView.open`
  (`SettingsView.swift:397`). Stored handoffs from older versions must still
  decode.
- **Existing "Report Reply":** unchanged. It exists for App Review 1.2 and
  stays an email.
- **Email fallback:** same pattern as `MivuLinks.reportReply`.
- **Privacy:** add "feedback you send us" to the privacy policy (private
  `mivu-site` repo) and draft the App Store privacy label change. The owner
  makes the label change in App Store Connect. Check whether
  `PrivacyInfo.xcprivacy` needs a collected-data entry.

## Constraints

- Follow `AGENTS.md`: failing test first, minimal Swift, platform APIs
  (`URLSession`, SwiftUI `Form`), Dynamic Type, VoiceOver, reduced motion,
  44-point targets.
- Tests use synthetic input only and never call the real endpoint.
- No hosted native CI; run focused native checks locally with XcodeBuildMCP and
  record the tested SHA.
- Nothing is logged that contains the message or the email address.
- No App Store upload until the owner says "publish".

## Left to the builder

Visual layout within the app's existing Settings style, exact wording, the
thank-you treatment, the Lambda runtime, and how the endpoint URL is configured
in the app.

## Amendments (2026-11-19, during the build)

1. **Server (owner decision):** the existing Cloudflare worker `mivu-reports` at
   `reports.mivuapp.com` (repo `mivu-infra`) gains a `POST /feedback` route. It
   replaces the Lambda and SES everywhere above, so nothing in AWS needs
   unblocking and no SES setup is needed. The worker already emails the owner's
   inbox and is rate limited; it costs nothing on the Cloudflare free plan. The
   owner applies it with terraform, then one configuration value in the app
   switches Send to the direct path. Request fields, limits and responses are
   unchanged.
2. **Coach link (builder's call):** Coach offers the existing Settings link and
   tells the person to tap Send feedback under Support, instead of a link that
   opens the form directly. A direct link needs a new value in the Coach
   destination that is stored in diary backups, which Android and older iOS
   versions read strictly, so a backup could become unreadable there. A direct
   link can follow with a backup-format change coordinated with Android.
3. **Report this problem (builder's call):** shown only on a turn that failed
   and needs a retry, not while Coach is waiting for the network or sign-in.
4. **Email rule (builder's call):** plain ASCII addresses only, the same rule
   in the app and the worker, because the address becomes a Reply-To header.
