#!/bin/zsh

set -euo pipefail

readonly expected_team_id="AL7WHQ783W"
readonly expected_app_group="AL7WHQ783W.com.michaeldev.VideoHero.Automation"
script_dir="${0:A:h}"
skill_root="${script_dir:h}"
require_checksum=false
if [[ "${1:-}" == "--require-checksum" ]]; then
  require_checksum=true
  shift
fi
cli="${1:-$skill_root/bin/macos-universal/videohero}"

if [[ "$cli" != /* || ! -x "$cli" ]]; then
  print -u2 "VideoHero CLI is missing or not executable: $cli"
  exit 2
fi

checksum_file="${cli:h}/videohero.sha256"
if [[ "$require_checksum" == true && ! -f "$checksum_file" ]]; then
  print -u2 "Missing checksum file: $checksum_file"
  exit 1
fi
if [[ -f "$checksum_file" ]]; then
  (
    cd "${cli:h}"
    /usr/bin/shasum -a 256 -c "${checksum_file:t}"
  )
fi

/usr/bin/codesign --verify --strict --verbose=2 "$cli"

archs="$(/usr/bin/lipo -archs "$cli")"
if [[ " $archs " != *" arm64 "* || " $archs " != *" x86_64 "* ]]; then
  print -u2 "VideoHero CLI is not universal: $archs"
  exit 1
fi

signature_info="$(/usr/bin/codesign -dv --verbose=4 "$cli" 2>&1)"
if [[ "$signature_info" != *"TeamIdentifier=$expected_team_id"* ]]; then
  print -u2 "Unexpected signing team; expected $expected_team_id"
  exit 1
fi
if [[ "$signature_info" == *"Signature=adhoc"* || "$signature_info" != *"runtime"* ]]; then
  print -u2 "VideoHero CLI must use a hardened non-ad-hoc signature"
  exit 1
fi

distribution=""
if [[ "$signature_info" == *"Authority=Developer ID Application:"* ]]; then
  distribution="developer-id"
elif [[ "$signature_info" == *"Authority=Apple Development:"* ]]; then
  distribution="development"
else
  print -u2 "Unsupported VideoHero CLI signing identity"
  exit 1
fi

entitlements_file="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/videohero-cli-entitlements.XXXXXX")"
trap '/bin/rm -f "$entitlements_file"' EXIT
/usr/bin/codesign -d --entitlements :- "$cli" > "$entitlements_file" 2>/dev/null
if ! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups' "$entitlements_file" 2>/dev/null \
  | /usr/bin/grep -Fq "$expected_app_group"; then
  print -u2 "VideoHero CLI is missing the Automation App Group entitlement"
  exit 1
fi
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlements_file" >/dev/null 2>&1; then
  print -u2 "Standalone VideoHero CLI must not have the App Sandbox entitlement"
  exit 1
fi

if [[ "$distribution" == "developer-id" ]]; then
  if [[ "$signature_info" != *"Timestamp="* ]]; then
    print -u2 "Developer ID CLI signature is missing a secure timestamp"
    exit 1
  fi
  spctl_output="$(/usr/sbin/spctl --assess --type execute --verbose=4 "$cli" 2>&1)" && spctl_status=0 || spctl_status=$?
  if (( spctl_status == 0 )); then
    print "Gatekeeper assessment passed"
  elif [[ "$spctl_output" == *"does not seem to be an app"* ]]; then
    print "Gatekeeper note: notarized standalone CLI is valid code but is not an App bundle"
  else
    print -u2 "$spctl_output"
    exit "$spctl_status"
  fi
else
  print -u2 "warning: Apple Development build; suitable for local testing only, not public distribution"
fi
"$cli" version --format json >/dev/null

print "VideoHero CLI verification passed: $cli"
print "Architectures: $archs"
print "Team ID: $expected_team_id"
print "App Group: $expected_app_group"
print "Distribution: $distribution"
