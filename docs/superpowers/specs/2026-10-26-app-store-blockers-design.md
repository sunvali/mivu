# App Store blocker fixes

Date: 26 October 2026, Asia/Jerusalem
Status: Approved by the owner in chat; implementation, focused tests and PR authorized.
Baseline: remote main 5afd977fcec8e9ceb256cfdd615748926b07e506 (1.1.1).

## Intent

Resolve the three source findings from the App Store review: app-managed health
archives written to iCloud, adult weight-loss calculations offered to teenagers,
and no way to report a generated Coach reply. Preserve existing records and the
native, private, fast-capture experience. Deliver focused test evidence and one
pull request based on refreshed main. Do not merge or publish as part of this task.

## Owner decisions and approaches

The owner selected these approaches after being offered alternatives:

1. **18+ only at launch.** This avoids introducing adolescent nutrition guidance.
   The alternatives were 13+ with restricted logging and full teen coaching with
   clinical input. Neither is in this release.
2. **Local backups and exports now.** The alternatives were other cloud file
   providers or a Mivu-hosted backup service. A Mivu-hosted service is the desired
   future direction, explicitly outside this PR. No backend scaffolding now.
3. **Email reporting to support@mivuapp.com.** The alternatives were a new report
   endpoint or a third-party ticketing service. Use the platform mail composer
   and require the person to review and send the message themselves.

The following details are proposed implementation calls, not prior owner
decisions. Approval of this document approves them.

## Age eligibility

- Introduce one shared eligibility rule for normal app use. A person confirms
  they are at least 18 before capture, automated targets, Coach inference or
  goal changes become available. Persist confirmation per local profile; it is
  not a global switch that authorizes every profile.
- Continue collecting only birth year in setup. A known year indicating under
  18 cannot be overridden by the adult confirmation. In the year a person turns
  18, explicit confirmation that their eighteenth birthday has passed is needed.
  Do not collect a full birthday or add identity verification in this PR.
- Existing profiles without confirmation require that confirmation before normal
  use. Existing known under-18 profiles stay readable and exportable but cannot
  capture new entries, receive advice, change goals, or resume pending inference.
  Never delete their records, queued requests, photos or connection credentials.
- Preserve the ability to delete a profile, disconnect the provider, read privacy
  and support information, and export existing data while normal use is gated.
  A restored archive must not carry a trusted adult confirmation to another
  profile/device; ask again after explicit restore/import.
- Enforce eligibility in shared runtime/mutation boundaries, not just disabled
  buttons. Include new and restored profiles, setup reruns, manual goal edits,
  Coach set_goals, quick capture, foreground resume and Siri/background inbox
  processing. A locked request that cannot establish eligibility asks the person
  to open Mivu; it must not send data or silently discard previously stored work.
- Keep import/schema validation separate from permission to use the app. A valid
  older archive is still readable even when its age is below the new minimum.
- Retain the existing adult calculation, BMI screen, pace and calorie floor.
  Treat these as product rules, not a guarantee of clinical safety. Do not apply
  a new universal manual calorie minimum as an unrelated change.

## Local health storage, backups and exports

### Destination and recovery

- The app writes backups and export files only to app-owned local storage.
  Remove the arbitrary destination picker for new writes. Removing the iCloud
  wording alone or checking a destination after export is insufficient.
- Maintain the versioned JSON-with-photos archive and existing validation,
  ownership, tombstone, cancellation and stale-revision rules. Reuse the current
  export coordinator and FolderBackup machinery wherever practical.
- Automatic local backup uses an app-owned destination and retains honest local
  acknowledgement/error states. A backup on the same phone does not protect
  against losing the phone. Display that distinction in the backup settings.
- Manual exports are saved in the app's local export area, visible for transfer
  through Files/Finder. Do not launch a generic save/share sheet that offers
  iCloud as an app-supported health export destination. Apply the same rule to
  the existing health PDF/CSV report export path.
- Files/Finder exposure must include portable export/backup files only, never the
  live SQLite database or operational metadata. Since the current live diary is
  in Documents/Diary, move operational storage to Application Support before
  enabling document/file-sharing access. Retain existing file protection.
- Migration happens before services open the diary. If both old and new stores
  exist or a move fails, preserve both and surface recovery instead of guessing
  which one to overwrite. Preserve operational backup metadata privately as well.
- An independently initiated move of an exported file in Files/Finder is outside
  the app's control. Copy must describe what Mivu itself does, never claim that
  iOS or the user cannot copy the data elsewhere.
- Import remains an explicit read-only selection of a portable archive, including
  an existing archive supplied by the person; restoration does not authorize
  future writes to its source folder.

### Existing configured destinations

- Before loading/scheduling the former external backup worker, prevent writes to
  all previously selected external destinations. Start local backup instead.
  This includes pending and resumed work, not just the choose-folder action.
- Preserve existing external archives and bookmarks. Explain that automatic
  external-folder writes stopped. Do not silently delete a cloud backup or use
  this change to overwrite an existing archive.
- Local profile deletion still removes active app-owned local data and backups.
  External copies made before the policy change remain user-managed; the app
  must say so instead of claiming every copy has been deleted. Update affected
  deletion tests and documentation to the new contract.

### Automatic system backup

- Mark the operational health-data directories and app-owned health exports as
  excluded from system backup. Cover legacy files before migration, the database
  and sidecars, pending Coach/inbox/proof files that can contain user content,
  local archives, and report exports. Reapply exclusion after writes/replacements
  that can clear resource values and verify the stored values in focused tests.
- Do not log health payloads, bookmark data, tokens or report contents.
- Apple's exclusion flag is advisory, not a guarantee that data never appears
  in an OS backup or restored device. Record this limit in verification; do not
  claim a programmatic absolute guarantee or Apple acceptance.

## Reporting a Coach reply

- Offer Report reply on generated Coach replies, alongside the existing actions.
  The report is bound to the selected profile and reply when initiated; profile
  changes or unavailable/deleted reply content cannot substitute another reply.
- Let the person choose a reason: unsafe advice, offensive content, inaccurate
  answer, or other; optional comments are allowed. Display the exact outgoing
  text for review before opening Mail.
- Include only the selected generated text, selected reason, optional comments,
  app version/build, provider/model when known, and an opaque reply reference.
  Do not automatically attach the originating prompt, history, photos, health
  profile, diary archive, device identifiers or credentials. Warn that the reply
  itself can contain personal health information. Sending is always explicit.
- Use MessageUI after canSendMail succeeds. Cancelled/saved drafts are not
  submitted reports. On the sent result say the report was queued in Mail,
  rather than claiming support received it. Failure preserves the review text.
- Without Mail configured, show the address and a user-initiated Copy report
  action so they can paste it into their own email client. Clearly state that
  copying does not send the report. Do not open other applications automatically.
- Add accessible support contact from Settings and a short response-handling
  document for the support inbox. The owner remains responsible for monitoring
  it and responding promptly; code cannot establish operational coverage.
- Add concise Coach safety instructions covering harmful dietary advice,
  dangerous restriction and inappropriate content. Keep diary estimation and
  medical advice clearly separated. Add deterministic tests of the instructions,
  reporting payload and cancellation/error states, but do not call prompt text
  or a mocked provider a proven production content filter. A synthetic live
  provider safety check remains a separately recorded acceptance step if it
  cannot be exercised in the available environment.

## Existing-app research

Research performed on 26 October 2026; competitors illustrate product patterns,
not evidence that Apple will approve Mivu's implementation.

An important qualification to the initial review: Foodnoms explicitly supports
iCloud sync for its food log and describes that log as personal health data.
Therefore iCloud use alone is not evidence of certain rejection. Apple's written
restriction still creates a review risk for Mivu's complete health/profile/chat
archives, but the selected local-only approach is a conservative product policy,
not a claim that every competing iCloud nutrition app violates the guidelines.
The owner must see this qualification before approving this design.

- MyFitnessPal requires age 18 or older:
  https://www.myfitnesspal.com/terms-of-service
- MyFitnessPal backs up to its own servers. This is a precedent for the owner's
  future cloud direction, not a reason to introduce that backend now:
  https://support.myfitnesspal.com/hc/en-us/articles/360032624511-How-do-I-make-sure-I-don-t-lose-my-data-when-I-delete-the-app
- Noom offers feedback after photo/voice/text meal logging. This supports placing
  feedback next to a result, but does not prove an offensive-content workflow:
  https://www.noom.com/support/faqs/using-the-app/logging-and-tracking/food-and-water/2025/10/how-to-log-meals-using-photo-voice-or-text/
- Foodnoms documents both iCloud and its own cloud as optional sync methods:
  https://foodnoms.com/help/account-and-privacy
  https://foodnoms.com/help/about-foodnoms
- Apple 1.2, 1.4, 5.1.3(ii), review access and privacy:
  https://developer.apple.com/app-store/review/guidelines/
- Apple MessageUI: composition can be unavailable and never proves delivery:
  https://developer.apple.com/documentation/messageui/mfmailcomposeviewcontroller
- Apple backup guidance: exclusion may be reset and is advisory:
  https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup

## Implementation adjustment after independent review

The review found that unconditional Documents sharing would expose a legacy live
SQLite directory before the first migration, or indefinitely after a conflict.
The implementation therefore keeps UIFileSharingEnabled and opening-in-place
sharing disabled. This supersedes the Files/Finder exposure described above.
Portable copies remain local, and an Export Diary Shortcuts action returns only
JSON, PDF or CSV files for explicit manual transfer. It requires authentication
on the iPhone itself and validates the selected profile before and after export.
No generic in-app destination picker or new cloud service is introduced. Files/
Finder visibility can be considered in a staged future migration release.
This is a builder decision to preserve the approved privacy boundary, not a
claim that the owner separately selected Shortcuts during brainstorming.

## Scope, tests and delivery

Use Swift and existing native components; no dependencies, backend, analytics,
new paid provider or new cloud system. Keep English, Dynamic Type, VoiceOver,
reduced motion and 44-point targets. Do not alter companion artwork or animation.

Focused tests cover eligibility at 17/18 and year boundaries, legacy profiles and
imports, manual/Coach parity and pending/background processing; migration and
conflict preservation, backup exclusion and external-write prevention, archive
roundtrip with photos and local export failures; report payload privacy, ownership,
reason selection, no-Mail fallback and Mail result wording. Reuse directly
affected suites rather than running the whole native plan. Run the required
120-second UI smoke on an explicitly reserved separate simulator and focused
UI coverage for the changed gates/report/backup actions. Never count zero tests,
timeouts, mock inference or an unavailable Mail account as a successful live test.

After design approval: write the implementation plan, refresh remote main, use
an isolated feature checkout, add failing focused tests, implement, review and
open the PR after the relevant checks pass. Record actual SHA, environment,
named results and remaining device/provider/App Store Connect gates. Follow the
repository PR/CI contract; PR and commit prose must not mention the prohibited
agent terms. Attach the created PR to this chat. No merge or public submission.

## Design review

A fresh native iOS builder reviewer read this design and reported "nothing
important left". The owner approved the design after the research qualification was presented. The research qualification
above was added after that check; it changes the stated confidence of the
initial iCloud finding, not the proposed implementation.
