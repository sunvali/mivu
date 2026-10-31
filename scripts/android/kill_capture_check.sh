#!/usr/bin/env bash
# Local check (not CI): a saved Coach capture survives process death.
# Needs a booted device/emulator and the debug APK (./gradlew :app:assembleDebug in android/).
set -euo pipefail

adb="${ADB:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb}"
apk="${1:-$(dirname "$0")/../../android/app/build/outputs/apk/debug/app-debug.apk}"
pkg=com.yakov103.mivu
probe="$pkg/.CaptureProbeActivity"
tag=MivuCaptureProbe

# Waits up to 30 s for a probe log line and prints its message.
await() {
  for _ in $(seq 30); do
    line=$("$adb" logcat -d -v raw -s "$tag:I" | grep -E "$1" | tail -1 || true)
    [ -n "$line" ] && { echo "$line"; return; }
    sleep 1
  done
  echo "timed out waiting for $1" >&2; exit 1
}

"$adb" install -r "$apk" >/dev/null
"$adb" shell am force-stop "$pkg"
"$adb" logcat -c
"$adb" shell am start -W -f 0x10008000 -n "$probe" >/dev/null
await '^CAPTURE_SAVED$' >/dev/null
pid=$("$adb" shell pidof "$pkg")

# am kill only stops background processes, so leave the probe and retry until its priority drops.
"$adb" shell input keyevent KEYCODE_HOME
for _ in $(seq 15); do
  "$adb" shell am kill "$pkg"
  sleep 1
  "$adb" shell pidof "$pkg" >/dev/null || break
done
if "$adb" shell pidof "$pkg" >/dev/null; then echo "process $pid still alive" >&2; exit 1; fi
echo "killed pid $pid during sleep"

"$adb" logcat -c
# NEW_TASK and CLEAR_TASK give a fresh task: relaunching the killed task would recreate the probe with its first (save) intent.
"$adb" shell am start -W -f 0x10008000 -n "$probe" --ez verify true >/dev/null
result=$(await '^CAPTURE_PRESENT=[01]$')
echo "$result"
[ "$result" = "CAPTURE_PRESENT=1" ] # the whole line: a flag only, no user data
