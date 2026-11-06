# Android setup comes back after a kill mid-setup

Recorded 2026-11-06. Why: in the end-to-end pass (`2026-11-06-android-e2e.md`), force-stopping the app during first-run
setup left Today with no targets on the next launch, and setup never returned. Testers who leave mid-setup would start
without targets.

- Tested source: `1ac836ce37208622ea93f136519781a9d9ab4095` on `fix/android-setup-resume`, from `main` at `ac06de57`. The record's
  own commit changes docs only.
- Environment: macOS 27.0, Android Studio JBR; emulator-5554 (`Medium_Phone_API_37.0`, API 37).
- Change: creating the first diary stores a per-diary "setup pending" preference. Setup opens on launch while it is set
  (once per process, so a rotation does not open it twice) and `onFinish` clears it: "Later", Back on the first step
  (review finding: Back dismissed the dialog and left the flag set), or saved targets.

## Results

| Scope | Result |
|---|---|
| `OnboardingScreenTest.setupReturnsAfterTheAppIsKilledUntilFinishedOrPutOff` (new) | failed first at the wait for "Hi, I'm Pip" after a fresh repository and composition; passes |
| `OnboardingScreenTest.backOnTheFirstStepPutsSetupOff` (new) | failed first with the old Back handling; passes |
| `OnboardingScreenTest` and `AppShellTest` (includes `newDiaryOpensSetupOnce`) | 22/22 |
| Minified release build at `ae934020` (before the Back change), fresh install, by hand: Get started → force-stop → reopen | setup shows again; after "Later" → force-stop → reopen, Today shows |

## Not run

- Unit tests and lint run in the pre-push hook. No full connected suite, no physical phone.
- iOS is unchanged and keeps the old behavior.
