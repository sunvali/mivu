# Android archive compatibility verification

Recorded 2026-10-24. Plan: Android storage, durable capture and archive compatibility.

## Task 1: iOS golden archive fixtures

- Source SHA tested: `3727cec1a6580cb5cb03bb8799bbad50b807c3d6`
- Fixtures: `fixtures/archive/ios-v4-full.json`, `ios-v1.json`, `ios-v2.json`, `ios-v3.json` (synthetic only).
- Environment: macOS 27.0.1, Xcode 27.0 (27A266a); dedicated simulator
  `mivu-archive-fixtures` (iPhone 17 Pro, iOS 26.5), deleted after the run.
- Generate (before the commit): the same command prefixed with `TEST_RUNNER_MIVU_WRITE_FIXTURES=1`.
  Two consecutive generations produced byte-identical files.
- Check (at the SHA, no write variable):

  ```sh
  xcodebuild test -project ios/Mivu.xcodeproj -scheme Mivu -testPlan Mivu \
    -destination 'id=<simulator UDID>' -only-testing:MivuTests/ArchiveFixtureTests
  ```

- Result: `ArchiveFixtureTests/fixturesMatchSyntheticSnapshot` passed; 1 test, 1 passed,
  0 failed, 0 skipped. A hand-edited `ios-v1.json` made the same test fail (file restored).
- Not covered: Android decoding of these files (later tasks).

## Tasks 2–8: Android wire format, model, validation, archive, store, capture, analysis

Environment for all Android runs: macOS 27.0.1, Android Studio JBR, Gradle; emulator
`Medium_Phone_API_37.0` (emulator-5554, API 37) for instrumented tests. Counts are summed from the
JUnit result XML. Each task showed RED (compile failure or a failing test) before GREEN.
These counts come from the earlier task reports at the listed SHAs and were not re-run for this record.

| Task | Source SHA tested | Result |
|---|---|---|
| 2 SwiftJson wire format | `c4be95a2b4ff79bc115769f1680ab948c28537a3` | `:app:testDebugUnitTest` 60 tests, 0 failed |
| 3 Diary model | `e2818e4075f7d00bb277ff7631e6b7c7672eb731` | `:app:testDebugUnitTest` 64 tests, 0 failed |
| 4 Validation | `cca9fdb4de3ff680a4404986f6a46352ab7cfb14` | `:app:testDebugUnitTest --rerun-tasks` 85 tests, 0 failed |
| 5 Archive decode/encode | `c8d886454342c3ed65938c2af6f785c426a2bcce` | `:app:testDebugUnitTest --rerun-tasks` 92 tests, 0 failed; all four iOS fixtures decode |
| 6 SQLite store | `f79708f75917ae82b5d6bff613fb9bc1d7664107` | `DiaryDatabaseTest` 20 instrumented, 0 failed; 92 unit, 0 failed |
| 7 Durable Coach capture | `3b75e9184d0a9495c0600334457f87d10af1e185` | `DiaryCaptureTest` 8 + `DiaryDatabaseTest` 20 instrumented, 0 failed; process-kill check found the capture present |
| 8 Analysis apply | `526a8a91345ba490aac4724ff1de667ac5519883` | full `:app:connectedDebugAndroidTest` 47 tests, 0 failed; 92 unit, 0 failed |

## Task 9: restore rules and both archive directions

- Source SHA tested: `c16ed85bc8c84814dcee273f6287daa88780e8dc`
- Android restore rules (`DiaryRestore.kt`, port of iOS `DiaryArchive.replacement` and
  `isVerifiedSuccessor`), JVM: `./gradlew :app:testDebugUnitTest --rerun-tasks` 97 tests,
  0 failed, 0 skipped. `DiaryRestoreTest`: `olderArchiveIsStale`, `unrelatedLineageIsStale`,
  `tombstoneResurrectionIsStale`, `verifiedSuccessorMerges`, `wrongOwner` (all 5 failed with the
  stub before the implementation).
- iOS → Android, instrumented on `Medium_Phone_API_37.0` (API 37): full
  `./gradlew :app:connectedDebugAndroidTest` 51 tests, 0 failed. `ArchiveRoundTripTest`:
  `androidExportImportsOnAndroidAndMatchesIosFixture` (import `ios-v4-full.json` into a fresh
  profile, export, import the export into another fresh profile; snapshots equal and all 4 photos'
  SHA-256 equal) and `importOverExistingDiaryUsesRestoreRules`. Both failed with the stub first.
  `writeAndroidFixture` and `importFiftyMegabytesOfPhotos` return immediately unless their
  instrumentation argument is set, so they count as passes in that run without doing work.
- Android → iOS: `android-v4-full.json` is Android's encoder output for the decoded
  `ios-v4-full.json` snapshot (JSON-equal to it, different key order). Generated with
  `adb shell am instrument -w -e writeFixtures true -e class com.yakov103.mivu.diary.ArchiveRoundTripTest#writeAndroidFixture com.yakov103.mivu.test/androidx.test.runner.AndroidJUnitRunner`
  and `adb exec-out run-as com.yakov103.mivu cat files/android-v4-full.json`.
- iOS check: Xcode 27.0 (27A266a), dedicated simulator `mivu-archive-android` (iPhone 17 Pro,
  iOS 27.0), deleted after the run:

  ```sh
  xcodebuild test -project ios/Mivu.xcodeproj -scheme Mivu -testPlan Mivu \
    -destination 'id=<simulator UDID>' -only-testing:MivuTests/ArchiveFixtureTests
  ```

  Result: `ArchiveFixtureTests/androidFixtureDecodesToSyntheticSnapshot` and
  `ArchiveFixtureTests/fixturesMatchSyntheticSnapshot` passed; 2 tests, 2 passed, 0 failed.
  With `android-v4-full.json` moved away, `androidFixtureDecodesToSyntheticSnapshot` failed
  (file not found), file restored.
- Memory ceiling (`importFiftyMegabytesOfPhotos`, `-e measureMemory true`): a synthetic archive
  with 5 photos of 10,000,000 random bytes (50 MB photos, 66,684,421-byte archive) imported in
  1.7 s. Java heap: 52 MB before, peak about 161 MB sampled, of a 192 MB limit
  (`Runtime.maxMemory`). The practical ceiling on this emulator is therefore roughly 60 MB of
  photos per archive for an import into a fresh profile; larger archives are likely to fail with
  OutOfMemoryError until photo decoding is streamed. Restoring over an existing diary holds both
  snapshots in memory, so its ceiling is roughly half (about 30 MB of photos). The 5 ms sampler can
  miss short allocation spikes, so the true peak may be higher than measured.
- Not covered: the system file picker / Drive journey for export and import (no UI yet), and
  real-device heap limits.
