#!/usr/bin/env bash
# Local check (not CI): an open manual-entry draft and a sample-mode composer draft (note, review toggle and a photo
# picked in the system photo picker) come back after the process is killed in the background.
# Needs a booted emulator in English and the debug APK (./gradlew :app:assembleDebug in android/).
# It clears the app's data and adds one synthetic picture to the device: run it only on a test emulator.
set -euo pipefail

adb="${ADB:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb}"
apk="${1:-$(dirname "$0")/../../android/app/build/outputs/apk/debug/app-debug.apk}"
pkg=com.yakov103.mivu
picture=/sdcard/Pictures/mivu-kill-restore.png

# Lines "label|x y" for every node with text or a content description on screen.
nodes() {
  "$adb" exec-out uiautomator dump /dev/tty 2>/dev/null | python3 -I -c '
import re, sys
for m in re.finditer(r"(?:text|content-desc)=\"([^\"]+)\"[^>]*bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"", sys.stdin.read()):
    print(f"{m[1]}|{(int(m[2]) + int(m[4])) // 2} {(int(m[3]) + int(m[5])) // 2}")'
}

# The centre of the first node whose label starts with $1, waiting up to 15 s.
at() {
  for _ in $(seq 15); do
    point=$(nodes | grep -F -- "$1" | head -1 | cut -d'|' -f2)
    [ -n "$point" ] && { echo "$point"; return; }
    sleep 1
  done
  echo "not on screen: $1" >&2; exit 1
}

tap() { point=$(at "$1") || exit 1; "$adb" shell input tap $point; }
expect() { at "$1" >/dev/null || exit 1; echo "restored: $1"; }
# Starts the app (extra arguments go to am start) and waits for Today.
launch() {
  for _ in 1 2 3; do
    "$adb" shell am start -W -n "$pkg/.MainActivity" "$@" >/dev/null
    for _ in $(seq 10); do nodes | grep -q "^kcal recorded|" && return; sleep 1; done
  done
  echo "Today did not open" >&2; exit 1
}
hide_keyboard() { "$adb" shell dumpsys input_method | grep -q mInputShown=true && "$adb" shell input keyevent KEYCODE_BACK; sleep 1; }

# am kill only stops a background process, so go home first and retry until its priority drops; then reopen the task
# from recents (am start on an existing task brings it to the front, and Android recreates it from saved state).
kill_and_reopen() {
  "$adb" shell input keyevent KEYCODE_HOME
  sleep 2 # let the activity stop and hand its saved state to the system
  pid=$("$adb" shell pidof "$pkg")
  for _ in $(seq 15); do
    "$adb" shell am kill "$pkg"; sleep 1
    "$adb" shell pidof "$pkg" >/dev/null || break
  done
  if "$adb" shell pidof "$pkg" >/dev/null; then echo "process $pid still alive" >&2; exit 1; fi
  echo "killed pid $pid in the background"
  "$adb" shell am start -n "$pkg/.MainActivity" >/dev/null 2>&1
}

"$adb" install -r "$apk" >/dev/null
"$adb" shell pm clear "$pkg" >/dev/null
"$adb" shell input keyevent KEYCODE_WAKEUP

echo "== Manual entry: Today > Add manually"
launch
tap "Add manually"
tap "Food name"; "$adb" shell input text "Synthetic%sapple"
tap "Energy (kcal)"; "$adb" shell input text "95"
hide_keyboard
kill_and_reopen
expect "Enter nutrition"
expect "Synthetic apple"
expect "95"
"$adb" shell am force-stop "$pkg"

echo "== Composer (sample mode): Today > Log meal"
python3 -I -c '
import struct, sys, zlib
w = h = 64  # a synthetic solid red square
chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
raw = b"".join(b"\x00" + b"\xc4\x30\x2b" * w for _ in range(h))
sys.stdout.buffer.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))' | "$adb" shell "cat > $picture"
"$adb" shell content call --method scan_volume --uri content://media --arg external_primary >/dev/null
launch --ez sampleMode true
tap "Log meal"
tap "Write what you ate"; "$adb" shell input text "Synthetic%stea"
hide_keyboard
tap "Photo library"
tap "Photo taken on" # the newest picture comes first
tap "Done"
at "Attached meal photo 1" >/dev/null || exit 1
hide_keyboard
tap "Review before saving totals"
kill_and_reopen
expect "Apple sample mode"
expect "Synthetic tea"
expect "Attached meal photo 1"
"$adb" exec-out uiautomator dump /dev/tty 2>/dev/null | grep -q 'checked="true"' || { echo "review toggle lost" >&2; exit 1; }
echo "restored: Review before saving totals (on)"
"$adb" shell am force-stop "$pkg"
"$adb" shell rm -f "$picture"
echo "PASS"
