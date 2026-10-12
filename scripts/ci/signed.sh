#!/bin/bash
set -euo pipefail
# Validate before touching any Apple service or local signing state.
required=(APPLE_DISTRIBUTION_P12_BASE64 APPLE_DISTRIBUTION_P12_PASSWORD
  APPLE_PROVISIONING_PROFILE_BASE64 APPLE_TEAM_ID)
if [ "${UPLOAD_TESTFLIGHT:-false}" = true ]; then
  required+=(ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY_BASE64)
fi
missing=()
for name in "${required[@]}"; do
  [ -n "${!name:-}" ] || missing+=("$name")
done
if [ "${#missing[@]}" -gt 0 ]; then
  printf 'Signed delivery blocked: missing owner secret %s\n' "${missing[@]}" >&2
  exit 1
fi
[ "${GITHUB_ACTIONS:-false}" = true ] && [ -n "${RUNNER_TEMP:-}" ] || {
  echo 'Signing runs only on an isolated Actions macOS runner.' >&2; exit 1;
}
cd "$(dirname "$0")/../.."
umask 077
signing_dir=$(mktemp -d "$RUNNER_TEMP/mivu-signing.XXXXXX")
keychain="$signing_dir/signing.keychain-db"
profile_path=''
cleanup() {
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  [ -z "$profile_path" ] || rm -f "$profile_path"
  rm -rf "$signing_dir"
}
trap cleanup EXIT
export SIGNING_DIR="$signing_dir"
python3 - <<'PY'
import base64, os, pathlib
p = pathlib.Path(os.environ['SIGNING_DIR'])
for name, target in [('APPLE_DISTRIBUTION_P12_BASE64', 'certificate.p12'),
                     ('APPLE_PROVISIONING_PROFILE_BASE64', 'profile.mobileprovision')]:
    try: data = base64.b64decode(''.join(os.environ[name].split()), validate=True)
    except ValueError: raise SystemExit('Invalid Base64 signing credential: ' + name)
    if not data: raise SystemExit('Empty decoded signing credential: ' + name)
    (p / target).write_bytes(data)
if os.environ.get('UPLOAD_TESTFLIGHT') == 'true':
    try: key = base64.b64decode(''.join(os.environ['ASC_PRIVATE_KEY_BASE64'].split()), validate=True)
    except ValueError: raise SystemExit('Invalid Base64 App Store Connect key.')
    if b'-----BEGIN PRIVATE KEY-----' not in key: raise SystemExit('Invalid App Store Connect private key format.')
    (p / 'AuthKey.p8').write_bytes(key)
PY
security cms -D -i "$signing_dir/profile.mobileprovision" > "$signing_dir/profile.plist" 2>/dev/null
profile_uuid=$(python3 - <<'PY'
import datetime, os, pathlib, plistlib, re
p = plistlib.loads((pathlib.Path(os.environ['SIGNING_DIR']) / 'profile.plist').read_bytes())
team = os.environ['APPLE_TEAM_ID']
if not re.fullmatch(r'[A-Z0-9]{10}', team): raise SystemExit('Invalid Apple team ID.')
if p.get('TeamIdentifier') != [team]: raise SystemExit('Provisioning profile belongs to another team.')
entitlements = p.get('Entitlements', {})
if entitlements.get('application-identifier') != team + '.com.yakov103.mivu':
    raise SystemExit('Provisioning profile must match the Mivu bundle identifier.')
if entitlements.get('get-task-allow') or p.get('ProvisionedDevices') or p.get('ProvisionsAllDevices'):
    raise SystemExit('An App Store distribution profile is required.')
if p.get('ExpirationDate', datetime.datetime.min) <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
    raise SystemExit('Provisioning profile expired.')
uuid = p.get('UUID', '')
if not re.fullmatch(r'[A-Fa-f0-9-]{36}', uuid): raise SystemExit('Invalid provisioning profile UUID.')
print(uuid)
PY
)
keychain_password=$(uuidgen)
security create-keychain -p "$keychain_password" "$keychain" >/dev/null 2>&1
security set-keychain-settings -lut 7200 "$keychain" >/dev/null 2>&1
security unlock-keychain -p "$keychain_password" "$keychain" >/dev/null 2>&1
security import "$signing_dir/certificate.p12" -P "$APPLE_DISTRIBUTION_P12_PASSWORD" \
  -t cert -f pkcs12 -k "$keychain" -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$keychain_password" "$keychain" >/dev/null 2>&1
security list-keychains -d user -s "$keychain" >/dev/null 2>&1
profile_path="$HOME/Library/MobileDevice/Provisioning Profiles/$profile_uuid.mobileprovision"
mkdir -p "$(dirname "$profile_path")"
cp "$signing_dir/profile.mobileprovision" "$profile_path"
export DEVELOPER_DIR
DEVELOPER_DIR=$(python3 - <<'PY'
import glob, re
paths = [p for p in glob.glob('/Applications/Xcode_26*.app/Contents/Developer')
         if not any(word in p.lower() for word in ('beta', 'rc'))]
if not paths: raise SystemExit('No stable Xcode 26 installation available.')
print(max(paths, key=lambda p: tuple(map(int, re.findall(r'\d+', p.split('.app')[0])))))
PY
)
output="$PWD/build/signed"
mkdir -p "$output"
if ! xcodebuild -resolvePackageDependencies -project ios/Mivu.xcodeproj -scheme Mivu \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution -skipPackageUpdates \
  > "$signing_dir/packages.log" 2>&1; then
  echo 'Locked Swift package resolution failed.' >&2; exit 1
fi
# Keep signing logs private: Xcode can include profile identifiers and private paths.
if ! xcodebuild archive -project ios/Mivu.xcodeproj -scheme Mivu -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$output/Mivu.xcarchive" \
  -derivedDataPath "$output/DerivedData" -onlyUsePackageVersionsFromResolvedFile \
  -disableAutomaticPackageResolution -skipPackageUpdates SWIFT_VERSION=6.0 \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Distribution' \
  PROVISIONING_PROFILE_SPECIFIER="$profile_uuid" OTHER_CODE_SIGN_FLAGS="--keychain $keychain" \
  CURRENT_PROJECT_VERSION="$GITHUB_RUN_NUMBER.$GITHUB_RUN_ATTEMPT" -quiet \
  > "$signing_dir/archive.log" 2>&1; then
  echo 'Signed archive failed. Check owner certificate/profile/bundle capabilities; private signing logs were withheld.' >&2
  exit 1
fi
export PROFILE_UUID="$profile_uuid" SIGNED_OUTPUT="$output"
python3 - <<'PY'
import os, pathlib, plistlib
options = dict(method='app-store-connect', destination='export', signingStyle='manual',
               teamID=os.environ['APPLE_TEAM_ID'], signingCertificate='Apple Distribution',
               provisioningProfiles={'com.yakov103.mivu': os.environ['PROFILE_UUID']},
               manageAppVersionAndBuildNumber=False, testFlightInternalTestingOnly=True, uploadSymbols=True)
p = pathlib.Path(os.environ['SIGNING_DIR'])
(p / 'ExportOptions.plist').write_bytes(plistlib.dumps(options))
options['destination'] = 'upload'
(p / 'UploadOptions.plist').write_bytes(plistlib.dumps(options))
PY
if ! xcodebuild -exportArchive -archivePath "$output/Mivu.xcarchive" \
  -exportPath "$output/ipa" -exportOptionsPlist "$signing_dir/ExportOptions.plist" \
  > "$signing_dir/export.log" 2>&1; then
  echo 'Signed IPA export failed; private signing logs were withheld.' >&2; exit 1
fi
find "$output/ipa" -maxdepth 1 -name '*.ipa' | grep -q . || { echo 'No signed IPA produced.' >&2; exit 1; }
if [ "${UPLOAD_TESTFLIGHT:-false}" = true ]; then
  if ! xcodebuild -exportArchive -archivePath "$output/Mivu.xcarchive" \
    -exportPath "$signing_dir/upload" -exportOptionsPlist "$signing_dir/UploadOptions.plist" \
    -authenticationKeyPath "$signing_dir/AuthKey.p8" -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" > "$signing_dir/upload.log" 2>&1; then
    echo 'TestFlight upload failed; owner credentials, Apple agreements or app configuration may block delivery. Private upload logs were withheld.' >&2
    exit 1
  fi
fi
python3 - <<'PY'
import datetime, json, os, pathlib, subprocess
record = dict(sourceCommit=subprocess.check_output(['git','rev-parse','HEAD'], text=True).strip(),
              utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
              workflowRun=os.environ['GITHUB_RUN_ID'], exitStatus=0,
              buildNumber=os.environ['GITHUB_RUN_NUMBER'] + '.' + os.environ['GITHUB_RUN_ATTEMPT'],
              signedIPA='exported for App Store Connect; not direct device installation',
              testFlight='upload acknowledged; Apple processing and tester availability unverified'
                         if os.environ.get('UPLOAD_TESTFLIGHT')=='true' else 'not requested')
(pathlib.Path(os.environ['SIGNED_OUTPUT']) / 'provenance.json').write_text(json.dumps(record, indent=2)+'\n')
PY
