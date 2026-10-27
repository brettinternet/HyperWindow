#!/usr/bin/env bash
set -euo pipefail
set -o noclobber

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 RELEASE_TAG [OUTPUT_DIR]" >&2
  echo "Set DEVELOPER_ID_IDENTITY, NOTARY_KEY_PATH, NOTARY_KEY_ID, and NOTARY_ISSUER_ID to sign and notarize." >&2
  exit 2
fi

tag=$1
output_dir=${2:-dist}
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/scripts/release-version.sh"
if ! release_version_parse "$tag"; then
  echo "package-release.sh: tag must match vMAJOR.MINOR.PATCH with an optional alpha, beta, or rc suffix: $tag" >&2
  exit 1
fi

signing_identity=${DEVELOPER_ID_IDENTITY-}
if [[ -n "$signing_identity" ]]; then
  for name in NOTARY_KEY_PATH NOTARY_KEY_ID NOTARY_ISSUER_ID; do
    if [[ -z "${!name-}" ]]; then
      echo "package-release.sh: $name is required when DEVELOPER_ID_IDENTITY is set" >&2
      exit 1
    fi
  done
  notary_auth=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
fi

output_dir=$(mkdir -p "$output_dir" && cd "$output_dir" && pwd)
archive="HyperWindow-${tag}-macos-universal.dmg"
for output in "$output_dir/$archive" "$output_dir/$archive.sha256"; do
  if [[ -e "$output" ]]; then
    echo "package-release.sh: refusing to overwrite existing output: $output" >&2
    exit 1
  fi
done

"$repo_root/scripts/build-release.sh" "$tag"
app_path="$repo_root/build/Build/Products/Release/HyperWindow.app"
staging=$(mktemp -d "${TMPDIR:-/tmp}/hyperwindow-release.XXXXXX")
mount_point="$staging/mount"
cleanup() {
  if [[ -d "$mount_point" ]]; then
    hdiutil detach "$mount_point" -quiet || true
  fi
  if [[ -x /usr/bin/trash && -e "$staging" ]]; then
    /usr/bin/trash "$staging" || true
  fi
}
trap cleanup EXIT

if [[ -n "$signing_identity" ]]; then
  # Explicit entitlements drop the get-task-allow entitlement Xcode adds to locally signed builds.
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements "$repo_root/HyperWindow/HyperWindow.entitlements" \
    --sign "$signing_identity" \
    "$app_path"
  codesign --verify --strict "$app_path"
fi

mkdir "$staging/dmg"
ditto "$app_path" "$staging/dmg/HyperWindow.app"
ln -s /Applications "$staging/dmg/Applications"
hdiutil create \
  -volname "HyperWindow $tag" \
  -srcfolder "$staging/dmg" \
  -ov \
  -format UDZO \
  "$output_dir/$archive"

if [[ -n "$signing_identity" ]]; then
  codesign --timestamp --sign "$signing_identity" "$output_dir/$archive"
  submission=$(
    xcrun notarytool submit "$output_dir/$archive" \
      "${notary_auth[@]}" \
      --wait \
      --output-format json
  )
  status=$(plutil -extract status raw -o - - <<<"$submission")
  if [[ "$status" != Accepted ]]; then
    echo "package-release.sh: notarization finished with status $status" >&2
    submission_id=$(plutil -extract id raw -o - - <<<"$submission")
    xcrun notarytool log "$submission_id" "${notary_auth[@]}" >&2 || true
    exit 1
  fi
  xcrun stapler staple "$output_dir/$archive"
  xcrun stapler validate "$output_dir/$archive"
  spctl --assess --type open --context context:primary-signature --verbose "$output_dir/$archive"

  mkdir "$mount_point"
  hdiutil attach "$output_dir/$archive" -readonly -nobrowse -mountpoint "$mount_point" -quiet
  assessment=$(spctl --assess --type execute --verbose=2 "$mount_point/HyperWindow.app" 2>&1)
  echo "$assessment"
  if [[ "$assessment" != *"source=Notarized Developer ID"* ]]; then
    echo "package-release.sh: Gatekeeper did not accept the app as notarized Developer ID" >&2
    exit 1
  fi
  hdiutil detach "$mount_point" -quiet
  rmdir "$mount_point"
fi

(
  cd "$output_dir"
  shasum -a 256 "$archive" > "$archive.sha256"
)

echo "Created $output_dir/$archive"
echo "Created $output_dir/$archive.sha256"
