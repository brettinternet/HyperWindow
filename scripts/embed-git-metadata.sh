#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 REPOSITORY_ROOT INFO_PLIST" >&2
  exit 2
fi

repo_root=$1
info_plist=$2
key=GitCommit

source "$(dirname "${BASH_SOURCE[0]}")/release-version.sh"

/usr/libexec/PlistBuddy -c "Delete :$key" "$info_plist" >/dev/null 2>&1 || true

while IFS= read -r tag; do
  if release_version_parse "$tag"; then
    exit 0
  fi
done < <(git -C "$repo_root" tag --points-at HEAD)

commit=$(git -C "$repo_root" rev-parse --short=7 HEAD)
/usr/libexec/PlistBuddy -c "Add :$key string $commit" "$info_plist"
