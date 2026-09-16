#!/bin/bash

set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
  echo "Usage: Scripts/create-dmg.sh <app-path> <dmg-path> <volume-name>"
  exit 0
fi

if [[ $# -ne 3 ]]; then
  echo "Usage: Scripts/create-dmg.sh <app-path> <dmg-path> <volume-name>" >&2
  exit 64
fi

app_path="$1"
dmg_path="$2"
volume_name="$3"

if [[ ! -d "$app_path" ]]; then
  echo "App bundle not found: $app_path" >&2
  exit 1
fi

case "$dmg_path" in
  *.dmg) ;;
  *)
    echo "DMG output must end in .dmg: $dmg_path" >&2
    exit 1
    ;;
esac

temporary_root="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/techne-dmg.XXXXXX")"
staging_directory="$temporary_root/contents"
cleanup() {
  rm -rf "$temporary_root"
}
trap cleanup EXIT

mkdir -p "$staging_directory" "$(dirname "$dmg_path")"
ditto "$app_path" "$staging_directory/Techne.app"
ln -s /Applications "$staging_directory/Applications"

hdiutil create \
  -volname "$volume_name" \
  -srcfolder "$staging_directory" \
  -format UDZO \
  -ov \
  "$dmg_path"

test -f "$dmg_path"
