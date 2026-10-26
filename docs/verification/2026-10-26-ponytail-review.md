# Ponytail Review — App Store blocker fixes

The report below is the independent review before fixes. All findings are now
resolved for the PR; native evidence and remaining device/service gates are in
[the verification record](2026-10-26-app-store-blockers.md).

## Resolution status

| Finding | Resolution | Verification |
|---|---|---|
| 1. Missing root blocks writes/deletion | Stop at lexical/canonical root path, preserving symlink checks | First writes, missing-export deletion and local file suites pass |
| 2. Documents exposure before migration | Leave sharing disabled; authenticated portable-only Shortcuts output | Built-app sharing assertions and all transfer formats pass |
| 3. Untested Siri age refusal | Add locked/unlocked unconfirmed-profile cases, another profile's flag and retained inbox | TellCoachTests pass |
| Supplement: export in-flight switch coverage | Add after-write away-and-back callback and selective cleanup assertion | Deliberately removed validation fails; restored validation passes |

The supplemental source review found no new product defect in the adapter.
Hardware protection, off-device transfer, Mail delivery, provider safety and
inbox operation remain unverified; the code verdict is readiness for review,
not an App Store approval decision.

## Original independent report

What this change does:
This change requires adult confirmation for each diary, moves operational health files into private local storage, and saves backups and exports on the phone. It also adds reviewed email reports for individual Coach replies, with a copy fallback and honest Mail status messages.

Assumed load: one native iPhone app with one shared diary writer for the foreground and Siri, multiple local profiles, and large paged histories; no backend. I reviewed the complete change against base 5afd977fcec8e9ceb256cfdd615748926b07e506, the approved design and plan, connected store and worker paths, migration and backup code, report presentation, and affected tests.

Must fix:

1. **A missing Exports folder blocks reports and profile deletion** (`ios/Mivu/Diary/LocalDiaryFiles.swift:L91-105`)
   - **What this is:** The ownership check walks up from an output path to its allowed local root before writing or deleting files.
   - **Problem:** When that root does not exist yet, the loop passes it and rejects its existing parent as outside the root. The first PDF/CSV export therefore fails, and deleting a profile before any export fails before deleting the diary; the new fresh-root atomic-write test has the same path.
   - **Fix:** Stop at the allowed root even when it does not yet exist, while still rejecting symbolic links along the path. Add focused cases for a first report and deletion with no Exports folder, and retain the external-link rejection test.
   - **If we skip it:** People cannot create their first report or delete their profile until a separate JSON export happens to create the folder.

2. **File sharing exposes operational health files before migration succeeds** (`ios/Config/Info.plist:L5-8`; `ios/Mivu/Diary/LocalDiaryFiles.swift:L25-36`)
   - **What this is:** The new app configuration exposes Documents through Files/Finder, while startup moves the old diary and backup metadata out of Documents.
   - **Problem:** An upgraded installation still has Documents/Diary before its first launch; a conflicting destination or failed move leaves it there indefinitely. File sharing therefore exposes the live database and operational metadata, even though the approved contract allows only portable exports and backups.
   - **Fix:** Do not enable whole-Documents sharing in a release that may still contain legacy operational files. Stage the private-storage migration before enabling sharing, or provide an export-only file surface; keep both conflicting copies and the recovery error intact.
   - **If we skip it:** The app makes private operational files browsable and transferable in the exact migration cases where it says those files need recovery.

Should fix:

3. **The Siri tests never exercise the new age refusal** (`ios/MivuTests/TellCoachTests.swift:L20-22,40-69`; `ios/Mivu/Coach/TellCoachIntent.swift:L24-35`)
   - **What this is:** Locked Siri checks a per-profile eligibility flag before saving an inbox entry; unlocked Siri checks the loaded profile before draining pending work.
   - **Problem:** Every Siri test now creates an eligible adult and sets the flag to true. Removing either new eligibility check can leave these tests passing, and no Siri test proves that existing pending entries survive a refused request.
   - **Fix:** Add focused locked and unlocked cases with a selected but unconfirmed profile and an existing inbox entry. Assert that Siri asks to open Mivu, no new capture or inference occurs, and the old entry remains unchanged; include another profile's true flag to verify isolation.
   - **If we skip it:** The shared background entry point can regress without a failing test, despite age gating and pending-work preservation being release requirements.

Verdict: fix 1 and 2 first.
Not checked: I did not run native tests or mutate product code; the parent owns the active storage-and-age run. Actual locked-device protection, configured Mail composer results, Files/Finder exposure on upgrade, live-provider safety, support-inbox operation, and App Store acceptance were not exercised in this review.

## Supplemental independent report

What this change does:
The new authenticated Export Diary action returns generated JSON, PDF or CSV files to Shortcuts without exposing the app's whole Documents folder. It checks the selected profile and selection epoch before reading, after reading, after writing, and again before returning files.

Should fix:

1. **The transfer tests do not exercise a profile change during export** (`ios/MivuTests/DiaryTransferTests.swift:L32-43`; `ios/Mivu/Diary/ExportDiaryIntent.swift:L30-31`)
   - **What this is:** The final ownership check rejects a file created while its original profile was being switched away and removes that output.
   - **Problem:** The stale-selection test switches profiles before calling the exporter, so it stops at the first check and never reaches cleanup. Removing the final ownership check and cleanup would leave every new transfer test passing.
   - **Fix:** Add a deterministic test that pauses after portable files are written, switches away and back to the same profile, then resumes publication. Assert that the changed selection epoch rejects the result and that generated files are removed while existing exports remain.
   - **If we skip it:** The security-sensitive late ownership boundary and cleanup can regress without a failing test.

No new concrete product-code defect found in this narrow review. Whole-Documents sharing is disabled; the original missing-root check now stops by path, and locked/unlocked Siri tests cover refused capture and preserved pending entries with another profile's true flag present.

Verdict: Ship.
Not checked: Native tests were not rerun. Actual Shortcuts/AirDrop transfer, protected-data refusal on a physical locked device, and system file protection remain unverified; the parent owns focused native checks.
