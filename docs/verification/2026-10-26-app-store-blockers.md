# App Store blocker verification — 26 October 2026

The owner approved an 18+ launch, local-only backups/exports, and reviewed email
reports. Implementation started from remote main
`5afd977fcec8e9ceb256cfdd615748926b07e506`, rechecked unchanged before delivery.

## Result

- Focused native units: **322 passed, 0 failed, 0 skipped**, in 44.097 seconds.
- Focused native UI: adult confirmation/persistence and local archive export
  passed in the first three-journey run; report-copy lookup initially failed
  because its control was offscreen. After fixing that test to scroll first,
  the report journey passed separately: **1 passed, 0 failed**, in 40.396 seconds.
  All three named journeys therefore have passing evidence. No Mail fixture
  was added; this is the actual simulator's available copy fallback.
- Required smoke: **1 passed**, **41.88 seconds**, within the 120-second cap.
  It covers offline text/photo capture, relaunch persistence, tabs and Settings.
- Project script checks: **42 passed**, 24.043 seconds. The timeout text inside
  their captured output is an intentional smoke-runner unit scenario.
- Whitespace and plist checks passed. No full native suite or release archive
  was requested or run.

Environment: XcodeBuildMCP, Debug Mivu scheme, iPhone 17 Pro simulator on iOS 26.5,
explicit UUID `42CE2315-9339-4EF1-A5B4-064444D0FA44`. Runs used a checkout-specific
DerivedData directory and the repository's per-simulator lock. No other worker's
simulator was reset or reused.

The native runs preceded the delivery commit against its working-tree inputs.
The app and unit-test files were fingerprinted unchanged after the 322-test run;
only the UI test's offscreen-control lookup changed afterward. The smoke ran
with the final complete native inputs. Delivery commits must preserve these
fingerprints; commit identity alone is not claimed as a post-commit rerun.

- App/unit input SHA-256: `a5219a9610222545a22b49feb1a9e5807163a663941a50fa9ed9ba1eeb7e1fb6`
- Complete native input SHA-256: `28c91f599bcff8316d3979378e106322f35785fd5101c2138452e0dbb0b65e6d`

## Regression evidence

The first six onboarding baseline tests passed. Age regressions then produced
three real failures before the implementation. The new export accounting
regression failed before confirmation updates included the exact contribution
and quota delta. Restores normalize local attestation before validating health
history, then require fresh confirmation.

The reporting ownership test failed when the final comparison deliberately
ignored selection epoch, then passed after restoration. The transfer race test
likewise failed with final ownership validation removed (**3 passed/1 failed**)
and passed in the 322-test run after restoration. Its callback switches away and
back after file creation, verifies rejection and removes only new files while
preserving older exports.

A real external symlink write was detected and fixed. The ownership walk now
checks existing ancestors and stops at the root path even when that root does
not exist yet. Whole-Documents exposure was reproduced in the built-app Info
values, then those sharing keys were removed. Locked/unlocked Siri refusal
cases retain old inbox entries and cannot borrow another profile's age flag.

One simulator launch failure returned a system Busy/preflight error and was
recorded as failed; it was not counted as passing application evidence.

## Ponytail Review

An independent reviewer read the complete change, callers, tests, approved
specification and plan at single-device/shared-writer load. It reported two
must-fix findings and one test gap. A focused supplement reviewed the newly
introduced authenticated export adapter and found no new product defect, but
requested one in-flight ownership test. All four findings were addressed.
See [the full review and resolutions](2026-10-26-ponytail-review.md).

## Implementation rulings

1. The app writes only to app-owned local destinations. Provider-name matching
   or checking a generic exporter destination after writing cannot establish the
   selected local-only policy. Existing external archives/bookmarks are retained.
2. Adult confirmation changes local access metadata without inventing a new
   health-history revision. Exact portable byte contributions remain atomic with
   that metadata change, and profile observers detect the updated confirmation.
3. Whole-Documents sharing stays disabled: old live databases may remain there
   before migration or during recovery. Export Diary in Shortcuts returns only
   portable JSON/PDF/CSV after on-iPhone authentication and owner/epoch checks.
   Manual transfer requires Shortcuts until a staged export-only Files surface
   exists. No cloud backend is scaffolded.

## Evidence locations (ignored build output)

- `build/review-evidence/final-focused-units/result.json` and `Mivu.xcresult`
- `build/review-evidence/focused-ui/result.json` and `Mivu.xcresult`
- `build/review-evidence/report-ui/result.json` and `Mivu.xcresult`
- `build/smoke/run-ql9d5nzx/` (result, xcresult and provenance)
- `build/review-evidence/script-checks.txt`
- `build/review-evidence/final-native-inputs.json`

## Unverified release gates

Actual locked-iPhone protection, Shortcuts/off-device transfer and configured
Mail delivery require physical-device proof. This simulator returns no file
protection metadata: simulator tests assert the requested atomic/protection
options and exclusion values, not hardware encryption. Backup exclusion remains
advisory. Live-provider safety, support-inbox monitoring, the public privacy
page's former iCloud wording, service authorization and App Store Connect /
signing / submission requirements remain separate gates. No external report was
sent, legal terms accepted, release uploaded or PR merged.
