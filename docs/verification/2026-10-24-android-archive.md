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
