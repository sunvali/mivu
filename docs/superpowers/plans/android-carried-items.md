# Android carried items

These items came out of reviews and must be picked up by the milestone named
on each one. Each milestone's plan reads this file and removes items once they
are done.

## Milestone 5 (live analysis)
- Add a model picker; the engine uses the first entry of the model catalog. iOS shows "Account model" only in the
  Settings ChatGPT connection section when connected, which is the Milestone 5 connection UI.
- Add the "Connect ChatGPT for replies" link under the composer. On iOS it starts sign-in, and release Android has no
  sign-in screen yet; until then the footnote stays "Messages save on this phone."
- Run the live Coach turn against ChatGPT once the owner has signed in on the emulator (Phase 0 evidence). It needs
  the sign-in UI.
- Sign-in showed only `NetworkUnavailable` when DNS failed. Show a clearer connection error, and note in the dev docs that the emulator may need `-dns-server 8.8.8.8`.
- `MealAnalysisWorker` must not hold its mutex across network calls. Remove
  duplicate drain requests with a flag instead.
- `StaleRevision` retries can cost up to 3 paid calls. Revisit this.
- Analysis failures are swallowed in `MivuApplication`. Surface them and offer
  Retry.

## Milestone 7 (Pip moments)
- Today Pip moments: saved, first meal today, day complete, welcome back, reviewed.

## Milestone 8 (outside-app capture)
- Coach reply notifications. iOS posts them only for Siri-started turns, and Android has no outside-app turn source
  until quick capture, share or Assistant arrive. Firing for every background turn would be new behaviour, not parity.

## Settings and day rollover
- Port the per-device day-cutoff setting. It is currently fixed at 04:00.
- Add the morning check-in, the weight row and the goal editor ("Set a goal" /
  "Edit goals" on Today).

## Play readiness
- Run a release-minify smoke test that decodes an archive fixture.
- Re-check `MaterialExpressiveTheme`. It did not compile with material3 1.4.0.
- Stream photo decoding for large archives, and add the export/import UI.
- Wire the profile button, or hide it.
- Check Pip's frame rate on an idle host or a real phone. On the loaded emulator the GPU took about 4950 ms per frame,
  so smooth playback could not be judged there; this is not a regression.
- Coach meal chip: the question's meal chip has an empty leading area where the mockup has an icon.
- Coach camera at font scale 2.0: "Choose photos" runs under the shutter.

## Later
- `record_source`: only fixes two invisible shortcuts, leftover photo copies after `delete_workout` and the
  `find_meals` origin fallback (meal seek uses the same fallback). The `shortcut:` comments stay until then.
