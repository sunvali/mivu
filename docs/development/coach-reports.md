# Coach reply reports

People can long-press a Coach answer and choose **Report reply**, or use the
named VoiceOver action. The native review shows the selected answer, one of
four reasons, an optional comment, app version/build, provider/model when
known, and the opaque reply reference. The current transcript does not retain
historical provider/model metadata, so these fields say Unknown rather than
using today's model selection.

Only this selected answer is copied into the report. The originating prompt,
conversation history, photographs, profile, diary archive, device identifiers
and credentials are not attached. The answer itself may contain personal
health information; the review warns about this before sending. Replies are
limited to 32 KiB without silent truncation; an oversized answer offers the
support address instead. Comments allow 1,000 characters and at most 4,000
UTF-8 bytes. Metadata fields are limited to 128 characters.

The report captures the selected profile, timeline generation, selection epoch
and turn. These ownership fields stay in memory and are not emailed. A bounded
store lookup checks the same reply when the review opens, after diary changes,
and before Mail or Copy. A different profile/selection, missing reply or changed
answer invalidates the review and dismisses any Mail composer. There is no
substitution of the latest reply or another profile's content.

**Review in Mail** opens Apple's MessageUI composer only when Mail is
configured. The person reviews and taps Send themselves. A sent callback means
the report was queued in Mail, with delivery unconfirmed. Cancelling does not
send a report; saving a draft does not submit one. Mail errors leave the review
text available for retry. The report is not persisted by Mivu and closing the
review discards its unsent comment. Mail may retain drafts the person chooses
to save, under their own mail account.

Without configured Mail, the review shows **support@mivuapp.com** and an explicit
**Copy report** button. Copying does not send anything; the person must paste it
into their email client and send it. Mivu does not open another application or
use an automatic reporting endpoint. The copied report remains on the system
clipboard according to iOS clipboard behavior.

## Support inbox handling

The owner is responsible for monitoring **support@mivuapp.com** and responding
promptly. Shipping this interface does not establish inbox monitoring, a
response-time commitment, successful delivery, or a production content filter.

For each received report:

1. Review the reported answer and reason. Prioritize unsafe dietary advice,
   dangerous restriction, and offensive content. Ask only for the minimum
   additional context needed; never request credentials or a full diary archive.
2. Acknowledge receipt and explain any next step. For health concerns, keep
   product troubleshooting separate from medical advice.
3. Record the opaque reply reference and app version for investigation. Treat
   quoted answers and comments as sensitive, restrict inbox access, and avoid
   copying report content into public issues, analytics, or application logs.
4. Investigate the relevant reply/safety path using synthetic reproductions.
   Track and address confirmed problems, then respond to the reporter when
   appropriate. Delete unnecessary copies according to the owner's support
   retention policy; this change does not establish that operational policy.

Focused payload/privacy/ownership/result tests live in
`ios/MivuTests/CoachReplyReportTests.swift`. Configured-Mail delivery, accessible
reason/comment review, profile changes with Mail open, and actual inbox
monitoring require separate device/operational verification.
