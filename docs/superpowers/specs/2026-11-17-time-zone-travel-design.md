# Time zone travel — design

## Why

Mivu's diary time zone is fixed when the profile is created. Travel never
changes it. An Israeli user who lands in New York gets a day that rolls over at
4 AM Israel time, which is 9 PM in New York, so dinner counts for tomorrow. Meal
times are inconsistent: Today shows the phone's zone, History shows the profile
zone and reports show the day's zone. The only fix is a text field where they type
`America/New_York`. The phone already knows where the user is. The diary should
follow it, quietly, without ever losing or moving a meal.

**Who it's for:** frequent flyers, people who change zone often (even weekly)
and expect it to just work. Every rule below favours zero prompts. A short trip
that stays on home time is a supported override, not the default.

## What others do (research)

- **MyFitnessPal:** the app rolls over by the phone's zone and the web by the
  profile's zone. Users get confused when the two disagree
  ([MFP community](https://community.myfitnesspal.com/en/discussion/10577408)).
- **Cronometer:** offers a pinned "preferred time zone". Travelers ask for
  automatic handling instead
  ([forum](https://forums.cronometer.com/discussion/1588/time-zone-support)).
- **Fitbit:** logs food to the previous day when the watch and phone zones disagree
  ([Fitbit community](https://community.fitbit.com/t5/Android-App/Food-logs-using-wrong-day/m-p/5320705)).
- **Apple Calendar:** follows the local zone and shows an event's original zone.
  Its pinned override is known for being forgotten
  ([Apple](https://support.apple.com/guide/ipad/schedule-display-events-a-time-zone-ipadb944fcd8/17.0/ipados),
  [TidBITS](https://tidbits.com/2025/03/19/understand-calendar-app-time-zone-support-to-avoid-scheduling-mishaps/)).
- **Apple Activity rings:** reset in the new zone. Flying east is the confusing
  case ([9to5Mac](https://9to5mac.com/2018/04/02/how-to-fill-apple-watch-activity-rings-while-traveling-timezones/)).
- **WHOOP:** notices the new zone when you land and welcomes you to the city.
  Users dislike that it re-times old sleep data into the new zone
  ([WHOOP](https://www.whoop.com/us/en/thelocker/2026-whats-new/),
  [community](https://www.community.whoop.com/t/sleep-consistency-in-sleep-planner-while-travelling-to-different-time-zones/13286)).

Takeaways: follow the phone, never re-time history, show where a time came from,
and make an override visible so it can't be forgotten.

## Goals

- The diary day, the "Day starts at" cutoff and new meal times follow the
  iPhone's time zone automatically.
- The day in progress on a travel day stays one diary day, however short or long.
- Every meal shows the clock time where it was eaten.
- Override: stay on the previous zone for a trip, from a toast or from Settings.
- Coach understands local time and the trip.

## Non-goals

- Jet-lag advice, meal-timing coaching, or a ChatGPT recap of the trip.
- Re-timing or moving past meals, days, weights or workouts.
- Syncing the setting across devices (Mivu has no account sync).
- Android in this change. iOS stays the source of truth, and `docs/parity.md`
  records the gap.
- Hebrew/RTL work (the MVP is English-only).

## Anti-goals (a failure even if it "works")

- A meal is lost, moved or duplicated by a zone change.
- A pending capture (Coach, Shortcut, Siri, photo) fails because the zone
  changed while it was being saved.
- The same date appears twice in History because of a mid-day change.
- A prompt or popup blocks logging after landing.
- The diary goes back a date (for example, flying west across the date line).

## Constraints

- The project's existing rules: platform APIs only, no new dependencies,
  Dynamic Type, VoiceOver, reduced motion, 44-pt targets, synthetic test inputs.
- Durable capture: an accepted capture keeps its own capture zone (this already
  holds for Coach turns).
- Existing profiles, archives and backups decode unchanged. New fields are
  optional.
- Native iOS builds and tests cannot run on the Linux workstation. Native
  evidence comes from XcodeBuildMCP on a Mac, with the source SHA recorded.

## Approaches

- **A. Keep the profile zone in step with the phone (chosen).** When automatic
  is on and the phone's zone differs, Mivu writes the device zone into
  `DiaryProfile.timeZoneID` through the existing profile update. Readers
  (cutoff, Coach context, Progress, reports) keep reading the profile zone.
  The places that assume "one zone for the whole diary" change: day lookup by
  date, the day assignment, Coach's day choice and the capture zone guard (§2,
  §2a, §8). Smallest change, and it reuses the path that Settings and Coach's
  `update_preferences` already take.
- **B. Work out the zone on each request.** About 20 call sites would ask a
  "current diary zone" helper instead of reading the profile. Nothing is saved,
  but every caller changes and the saved profile zone loses its meaning. It's
  more risk for the same behavior.
- **C. A `followsDevice` flag in the profile.** The setting would travel with
  backups, but it changes the profile schema, which archives and Android must
  handle. Without device sync it buys nothing.

The owner picked A.

## Behavior

### 1. Following the phone

- A device preference `timeZoneMode` stores one of two values: `automatic`
  (the default), or `pinned(zone, untilDeviceZone?)`. It lives in
  `UserDefaults`, like `DayCutoff`, and is kept **per profile** (keyed by
  profile ID), because the app has several local profiles. A profile is synced
  when it becomes the selected profile and at every sync point.
- **Sync point:** before every activity, Mivu compares `TimeZone.current` with
  the profile zone. Activity means the app coming to the foreground, a
  `NSSystemTimeZoneDidChange` while it's open, and any log (meal, weight,
  Coach, manual nutrition, Shortcut, Siri/App Intent, quick-log camera). Sync
  runs before the existing day rollover check, so the cutoff is judged in the
  new zone.
- When automatic is on and the zones differ, Mivu updates the profile's
  `timeZoneID` to the device zone. History is never rewritten: existing days,
  meals and goals keep their stored zones and dates. Weights linked to a day keep
  that day's date. New weights must always link a day. Legacy weights with no
  `dayID` are dated in the profile zone, so one can display a date off while
  away. That's accepted, since it's rare legacy data.
- The sync does not run while a Coach request or capture for that profile is in
  flight. It runs right after, so a reply never goes stale because the
  revision changed mid-reply.
- `updateProfile` clearing `previousDayConfirmedAt` on a zone change stays. The
  field no longer drives decisions (day rollover design), so it's harmless.
- **Existing profiles on first launch after the update:** every profile starts
  in `automatic`. A stored zone that differs from the device zone is usually
  stale (the old app never followed the phone), so the first sync switches to
  the device zone and announces it; "Keep <city>" restores a zone that was
  chosen on purpose. (Changed 2026-11-17 after an owner device test: pinning
  on a mismatch silently kept a stale Jerusalem diary in New York.)
- An explicit zone change by the user (the Settings picker, or Coach's
  `update_preferences` timezone) sets the mode to match. The device zone means
  automatic; any other zone means pinned with no auto-release.
- **Captures in flight:** a capture rejected as stale because the zone changed
  is retried, never dropped or shown as an error. The retry sends the **same payload and
  manifest**, including its original context, per the durable-capture rule.
  Reconciliation by submission ID then still matches if the first attempt
  committed. To let that retry save, `captureCoachSubmission` drops the
  `context.timeZoneID == profile.timeZoneID` check. The active-day,
  previous-day and conversation-segment checks remain. The capture's own zone
  is the truth for that capture. Accepted Coach turns keep their saved capture
  zone, as today.

### 2. The travel day

- The day in progress stays the active day until the waking date in the
  **current** profile zone passes it (the first activity after the next cutoff
  in the new zone). This changes `dayAssignment`: it currently returns
  `.newDay` whenever the active day's zone differs from the profile zone. That
  condition is removed, and only the date comparison remains.
- New days are created in the current profile zone. The travel day keeps its
  original zone and date, so no date is duplicated.
- **Never back a date:** when the waking date in the new zone is earlier than
  the active day's date (flying west across the date line), the active day
  continues. This is the existing `localDate >= waking` rule, kept.
- Worked examples (cutoff 4 AM):
  - Tel Aviv 10:00 Nov 17 → New York 15:00 Nov 17: the same day continues. It
    rolls over at 4 AM Nov 18 New York time.
  - Tel Aviv 18:00 Nov 17 → Tokyo 13:00 Nov 18: the first activity in Tokyo
    starts Nov 18 (Tokyo).
  - Tokyo 09:00 Nov 18 → Honolulu 20:00 Nov 17: Nov 18 continues until 4 AM
    Nov 19 Honolulu time.
- The morning card and the "Added to … · Change" receipt keep their existing
  rules, judged in the current zone.

### 2a. One day per date

A date has one diary day, whatever zone it was opened in.

- Every lookup that finds or creates a day by date matches on **date only**:
  `resolveDay`, as used by `startDay`, `setWeight`, `createWorkout`,
  `weightReceiptDay`, `coachDay`, and the manual-nutrition `.newCurrent` check.
  An existing day for that date is reused, whatever its zone. A new day is
  created in the current profile zone only when that date has no day yet.
- Old diaries that already have two days with the same date: prefer the active
  day, otherwise the earliest by `startAt`. Nothing is merged or rewritten.
- **"Start new day" never goes back a date.** If the date it would open is the
  active day's date or earlier (westward across the date line), it opens the
  day after the active day.
- Moving a meal to an existing earlier day stays allowed. It doesn't change the
  active day, so it's not "going back".

### 3. Meal times

- `DiaryMeal` gains an optional `timeZoneID`: the zone where it was eaten. It is
  set on every new capture to the zone in effect at capture, and kept by edits
  and moves. Older meals have `nil` and fall back to their day's zone.
- Every place that shows a meal's time shows it in the meal's zone: the Today
  list, meal detail, History, Coach chips and history, and reports and exports.
- When the meal's zone shows a different clock time from the phone's current
  zone, a small secondary tag follows the time, using the city name ("Tel
  Aviv"). VoiceOver reads it as "7:40 AM, Tel Aviv time".
- Moving a meal to another day validates its date in the meal's zone, not the
  day's. Otherwise a New York dinner on a Tel Aviv-zoned travel day would be
  rejected as invalid.

### 4. The toast

- When sync switches the zone (automatic mode) **and** the clock time differs,
  meaning the UTC offset at that moment changed, show a toast on whichever tab
  is visible: "Now on New York time · Keep Tel Aviv".
- Same-offset changes (Paris → Berlin) switch silently. A change that flips
  back within an hour, or a second flip within an hour, shows no toast
  (border jitter). The zone still follows the phone.
- **"Keep Tel Aviv"** restores the profile zone to Tel Aviv and sets
  `pinned(Tel Aviv, untilDeviceZone: Tel Aviv)`. When the phone is back on Tel
  Aviv time, the mode returns to `automatic` by itself, with no toast. Undo
  happens before any further logging. Keeping it is safe because no meal was
  re-timed.
- The toast never blocks logging. It dismisses on its own, uses the existing
  toast/receipt style, and is announced to VoiceOver. A shortcut log without
  the UI shows no toast; the next open shows it once if the change is still
  recent (same day).

### 5. Pinned hint

- While the mode is pinned and the profile zone shows a different clock time
  from the phone, Today's date header shows a small tag: "Tel Aviv time ›".
  Tapping it offers "Use New York time", which switches to automatic.

### 6. Settings

- The "Timezone" text field is replaced by an iOS-style section:
  - **Set automatically** toggle (on = `automatic`).
  - **Time zone** row: shows the city. Greyed out while automatic. When off,
    it opens a searchable list of cities (from `TimeZone.knownTimeZoneIdentifiers`,
    shown as localized city names with GMT offsets). Choosing one pins with no
    auto-release.
- The explanatory footer becomes: "Earlier meals keep the time where you ate
  them." The old "You may be asked which waking day to use" line is removed.
- The existing draft and conflict handling for the profile still applies.

### 7. Travel-day marker

- A day whose meals (by meal zone, with the day zone as fallback) span more
  than one UTC offset shows a small ✈︎ next to its date in History and in
  Progress day lists. It is not shown on Today. Its VoiceOver label is
  "Travel day".
- The day counts in stats like any other day. The existing "skip day" coverage
  option still lets the user leave it out.

### 8. Coach

- Coach's context already carries the capture instant and zone. On a day that
  is a travel day (per §7, or where the profile zone changed since the active
  day began), the developer context also says, for example, "Local time
  15:10 in New York; arrived from Tel Aviv today; the open diary day is Tue,
  Nov 17."
- The early-morning rule (late-night snack versus breakfast) uses local time in
  the current zone.
- Relative times the user says ("a sandwich at 2pm") mean the current zone.
- **"Today" for Coach is the open diary day.** "Yesterday" is the day before it,
  even when the local calendar date differs (Honolulu on an open Nov 18).
  `coachDay` no longer throws `ambiguousDay` just because the turn's capture
  date in its zone differs from the open day across a travel change. It applies
  the same open-day rule as `dayAssignment`.
- The Coach `.startDay` guard that requires `turn.captureTimeZoneID ==
  profile.timeZoneID` is relaxed. A turn accepted before landing and answered
  after it still applies, judged by dates and the open-day rule, not by zone
  equality.
- No new ChatGPT calls. The on-device Apple Intelligence path gets the same
  context text.

### 9. Everything else

- **Morning reminder:** stays a floating `UNCalendarNotificationTrigger`, so it
  fires at 8 AM wherever the phone is. No change.
- **Widget and Live Activity:** already use the active day's or profile's zone
  for the next rollover. After sync they follow the new zone. Rewrite the
  snapshot after a sync.
- **Pip greeting** (`PipLine`, device hour): matches the diary in automatic
  mode. In pinned mode it keeps the device hour; that's acceptable.

## Tests (smallest meaningful, written first)

Unit (`ios/MivuTests`):
- The sync switches the profile zone in automatic mode, does nothing when
  pinned, and releases a trip pin when the device returns to the pinned zone.
- The migration default: always automatic; a different stored zone switches
  to the device zone and announces it, with Keep.
- `dayAssignment` keeps a different-zone active day until the new zone's waking
  date passes it, and never goes back a date. Covers the three worked examples.
- Logging a weight, workout or manual meal for the travel date after the sync
  reuses the existing day: no second day with the same date.
- "Start new day" in the Honolulu case opens Nov 19, not Nov 17.
- A Coach turn accepted under Tel Aviv and applied after the sync to New York
  saves to the open day, with no `ambiguousDay`.
- The mode is per profile: switching profiles never moves another profile's pin.
- A new meal records its `timeZoneID`. Older payloads without it decode, and
  the meal falls back to the day's zone.
- A capture prepared before a zone change is retried and saved once, never lost.
- Toast decision: an offset change shows the toast; same-offset and flip-back
  within an hour don't.
- Travel-day detection across two offsets.
- Meal time formatting: tag only when the clock differs; VoiceOver label.

UI: one test with a synthetic zone change. The toast appears, "Keep" pins it,
and the header tag shows. Plus `scripts/ci/smoke.py` for the Settings/Today
change. Run with XcodeBuildMCP on a reserved simulator; record the SHA and
result bundle.

## Left to the builder

- The exact toast copy and duration, and how the city name is derived from a
  zone identifier.
- Where the sync helper lives (view model versus store), as long as every log
  path, including App Intents, calls it before saving.
- Whether "flip-back within an hour" needs stored state or can be derived from
  the last switch time.
- The visual design of the ✈︎ marker and the header tag, within the design
  system.
