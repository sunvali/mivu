# Mivu overnight MVP execution addendum

Date: 2026-10-12, Asia/Jerusalem. Direct owner instruction: implement continuously
until a working native MVP and full GitHub Actions CI/CD exist; use an apple
image/prompt result until ChatGPT work resumes; do not wait for feedback.
This overrides the prior live-connection prerequisite and skill review pauses.
It does not authorize paid membership/resources, public publication, or accepting
legal terms. The accepted 2026-10-11 product spec remains the product contract.

## Current release scope

Today is the first screen. Camera/library/text/both capture saves before returning
home; every capture receives the same visibly synthetic one-medium-apple estimate,
never claimed recognition. Quick save and review-first both work. Meals retain
photos until deletion and support direct item edits, same-meal text/photo additions,
half-portion correction, undo/deletion, revision guards, and move between days.
Recorded totals use committed numeric items only, preserving unknown nutrients.
Waking days support 04:00 previous-day assignment, one ambiguous-day question with
four-hour/date expiry, explicit start and optional morning weight, configurable
timezone without silently moving history, completeness and earlier-day summaries.

Use a local app-owned profile independently from ChatGPT. Protected per-profile
storage and queues isolate profile switching; reconnect does not erase records.
Settings include language, preferences, timezone, sample-mode explanation, the
existing connection diagnostic, backup/export/restore, and deletion. Account
switch/logout preserves isolated unsynced records; explicit delete removes them.
No scoring, diet recommendations, paid provider, server framework or Siri beta
is needed for this release. Physical phone/14-day pilot evidence must never be
invented; automate simulator acceptance and state any actual device gates.

## Backup choice for this release

Use a private user-selected Files folder (iCloud Drive is available when enabled
on the phone) through a security-scoped directory bookmark. Automatically write
one versioned, self-contained JSON archive with photo data after acknowledged
local mutations while the app can execute. Local acknowledgement and destination
acknowledgement are separate. File-provider write acknowledgement is not proof
of remote iCloud upload: display "Saved to backup folder", timestamp and pending
errors, not "Cloud synced". Export/import use the same portable JSON+media schema,
without credentials. A fresh local profile can restore a chosen owned backup.
Do not auto-merge older backups into current data; confirm replacement in the app.
Revision/tombstone validation prevents late work or stale backups resurrecting
explicitly deleted content. The backup worker must propagate deletions to its
selected archive and surface failures. This uses no purchased Apple capability.
CloudKit/account-authenticated remote restore remains later provider work; the
MVP must provide an actually tested acknowledged archive roundtrip including photos.

## Delivery contract

GitHub Actions checks pull requests and main, builds/tests native simulator
products, preserves xcresult and app artifacts, and publishes versioned release
artifacts from an explicit tag/manual release. Signed IPA/TestFlight delivery
must be supported when owner-provided Apple signing/App Store credentials exist;
missing signing must fail the signed lane clearly, never label an unsigned build
installable. Do not run a paid hosted runner until included allowance is verified.
Do not enable billing. Establish evidence from actual workflow runs rather than
workflow YAML alone. Repository remains private unless separately authorized.

## Appearance

Use native SwiftUI navigation and controls with a warm neutral surface, restrained
teal accent, clear meal rows, large capture action, and concise status copy. System
type scales, dark mode follows the system, all actions are at least44pt, English
LTR/Hebrew RTL, VoiceOver labels and reduced-motion behavior remain requirements.
Sample mode is visible in the diary and each synthetic estimate's provenance.
