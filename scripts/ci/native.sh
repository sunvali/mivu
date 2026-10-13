#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mode=${1:-test}
case "$mode" in unit|test|release|unsigned) ;; *) echo 'Use native.sh unit|test|release|unsigned' >&2; exit 2 ;; esac
output=${MIVU_CI_OUTPUT:-$PWD/build/ci}
mkdir -p "$output"
record_provenance() {
  status=$?
python3 - "$output" "$mode" "$status" <<'PY'
import datetime, json, os, pathlib, platform, subprocess, sys
p = pathlib.Path(sys.argv[1])
record = dict(sourceCommit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
              utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
              environment=platform.platform(), mode=sys.argv[2],
              workflowRun=os.environ.get('GITHUB_RUN_ID'), exitStatus=int(sys.argv[3]),
              installability='unsigned; not installable on a physical iPhone' if sys.argv[2]=='unsigned' else 'simulator only')
(p / (sys.argv[2] + '-provenance.json')).write_text(json.dumps(record, indent=2)+'\n')
PY
}
trap record_provenance EXIT
# Choose a stable Xcode 26 installation, never the image's beta default.
export DEVELOPER_DIR
DEVELOPER_DIR=$(python3 - <<'PY'
import glob, re
paths = glob.glob('/Applications/Xcode_26*.app/Contents/Developer')
def version(path):
    return tuple(int(n) for n in re.findall(r'\d+', path.split('.app')[0]))
paths = [p for p in paths if not any(word in p.lower() for word in ('beta', 'rc'))]
if not paths:
    raise SystemExit('No stable Xcode 26 installation available.')
print(max(paths, key=version))
PY
)
xcodebuild -version | tee "$output/xcode-version.txt"
xcrun swift --version | tee "$output/swift-version.txt"
xcodebuild -showsdks > "$output/sdks.txt"
xcrun swift --version | head -1 | grep -Eq 'Swift version 6\.'
# No package version may drift from the committed lockfile.
common=(-project ios/Mivu.xcodeproj -scheme Mivu -derivedDataPath "$output/DerivedData"
  -clonedSourcePackagesDirPath "$output/SourcePackages"
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution
  -skipPackageUpdates SWIFT_VERSION=6.0)
xcodebuild -resolvePackageDependencies "${common[@]}" -quiet
if [ "$mode" != unsigned ]; then
  destination=$(xcrun simctl list devices available --json | python3 -c '
import json, platform, re, sys
candidates = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if match and int(match[1]) >= 26:
        for device in devices:
            if device.get("isAvailable") and device["name"].startswith("iPhone"):
                candidates.append(((int(match[1]), int(match[2])), device["name"], device["udid"]))
if not candidates: raise SystemExit("No available iPhone simulator with iOS 26 or newer.")
print("platform=iOS Simulator,arch=" + platform.machine() + ",id=" + max(candidates)[2])')
  set +e
  test_scope=()
  if [ "$mode" = unit ] || [ "$mode" = release ]; then test_scope=(-only-testing:MivuTests); fi
  xcodebuild test "${common[@]}" -configuration Debug -destination "$destination" \
    "${test_scope[@]}" -parallel-testing-enabled NO -resultBundlePath "$output/Mivu.xcresult" -quiet
  test_status=$?
  set -e
  if [ -d "$output/Mivu.xcresult" ]; then
    xcrun xcresulttool get test-results summary --path "$output/Mivu.xcresult" > "$output/test-summary.json"
    xcrun xcresulttool get test-results tests --path "$output/Mivu.xcresult" > "$output/test-cases.json"
    python3 scripts/ci/verify_results.py "$output"
  else
    echo 'Missing xcresult; native tests did not complete.' >&2
    exit 1
  fi
  [ "$test_status" -eq 0 ] || exit "$test_status"
  if [ "$mode" = release ]; then
    xcodebuild build "${common[@]}" -configuration Release -destination 'generic/platform=iOS Simulator' -quiet
    ditto -c -k --keepParent "$output/DerivedData/Build/Products/Release-iphonesimulator/Mivu.app" \
      "$output/Mivu-simulator.app.zip"
  fi
else
  xcodebuild archive "${common[@]}" -configuration Release -destination 'generic/platform=iOS' \
    -archivePath "$output/Mivu-unsigned.xcarchive" CODE_SIGNING_ALLOWED=NO -quiet
  test -d "$output/Mivu-unsigned.xcarchive/Products/Applications/Mivu.app"
  ditto -c -k --keepParent "$output/Mivu-unsigned.xcarchive" "$output/Mivu-unsigned.xcarchive.zip"
fi
