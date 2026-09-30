#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-anotherlatenight/obsidian-quick-note-task}"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
APP_DEST_DIR="/Applications"
EXPECTED_TEAM_ID="${EXPECTED_TEAM_ID:-}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd curl
require_cmd hdiutil
require_cmd python3
require_cmd ditto
require_cmd codesign
require_cmd spctl
require_cmd shasum

if [[ -z "$EXPECTED_TEAM_ID" ]]; then
  echo "Set EXPECTED_TEAM_ID to the publisher's verified Apple Developer Team ID before installing." >&2
  exit 1
fi

echo "Fetching latest release from ${REPO}..."
RELEASE_JSON="$(curl -fsSL "$API_URL")"

ASSET_METADATA="$(python3 -c '
import json
import sys

release = json.load(sys.stdin)
for asset in release.get("assets", []):
    url = asset.get("browser_download_url", "")
    expected_prefix = "https://github.com/" + sys.argv[1] + "/releases/download/"
    if url.startswith(expected_prefix) and url.endswith(".dmg"):
        print(url + "\t" + (asset.get("digest") or ""))
        break
' "$REPO" <<< "$RELEASE_JSON")"

IFS=$'\t' read -r DMG_URL RELEASE_DIGEST <<< "$ASSET_METADATA"

if [[ -z "$DMG_URL" || ! "$RELEASE_DIGEST" =~ ^sha256:[[:xdigit:]]{64}$ ]]; then
  echo "No DMG with a valid SHA-256 digest found in latest release." >&2
  exit 1
fi

EXPECTED_SHA256="${RELEASE_DIGEST#sha256:}"

TMP_DIR="$(mktemp -d -t oqnt-install-XXXXXX)"
DMG_PATH="$TMP_DIR/$(basename "$DMG_URL")"
MOUNT_POINT=""

cleanup() {
  if [[ -n "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "Downloading DMG..."
curl -fL "$DMG_URL" -o "$DMG_PATH"
ACTUAL_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
if [[ "${ACTUAL_SHA256,,}" != "${EXPECTED_SHA256,,}" ]]; then
  echo "DMG SHA-256 does not match the GitHub release digest." >&2
  exit 1
fi

echo "Mounting DMG..."
ATTACH_PLIST="$TMP_DIR/attach.plist"
hdiutil attach "$DMG_PATH" -nobrowse -readonly -plist > "$ATTACH_PLIST"

MOUNT_POINT="$(python3 - "$ATTACH_PLIST" <<'PY'
import plistlib
import sys

with open(sys.argv[1], 'rb') as f:
    data = plistlib.load(f)

for entity in data.get('system-entities', []):
    mp = entity.get('mount-point')
    if mp:
        print(mp)
        break
PY
)"

if [[ -z "$MOUNT_POINT" ]]; then
  echo "Failed to detect mounted volume." >&2
  exit 1
fi

APP_SOURCE="$(find "$MOUNT_POINT" -maxdepth 1 -type d -name '*.app' | head -n 1)"
if [[ -z "$APP_SOURCE" ]]; then
  echo "No .app found in mounted DMG." >&2
  exit 1
fi

if [[ "$(basename "$APP_SOURCE")" != "ObsidianQuickNoteTask.app" ]]; then
  echo "Unexpected application bundle in release DMG." >&2
  exit 1
fi

echo "Verifying application signature and Gatekeeper assessment..."
codesign --verify --deep --strict --verbose=2 "$APP_SOURCE"
SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "$APP_SOURCE" 2>&1)"
ACTUAL_TEAM_ID="$(printf '%s\n' "$SIGNATURE_DETAILS" | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
if [[ -z "$ACTUAL_TEAM_ID" || "$ACTUAL_TEAM_ID" != "$EXPECTED_TEAM_ID" ]]; then
  echo "Application Team ID does not match EXPECTED_TEAM_ID." >&2
  exit 1
fi
spctl --assess --type execute --verbose=2 "$APP_SOURCE"

APP_NAME="$(basename "$APP_SOURCE")"
DEST_PATH="$APP_DEST_DIR/$APP_NAME"

echo "Installing $APP_NAME to $APP_DEST_DIR..."
if [[ -e "$DEST_PATH" ]]; then
  echo "An app already exists at $DEST_PATH. Move it aside or remove it manually, then rerun the installer." >&2
  exit 1
fi

if [[ -w "$APP_DEST_DIR" ]]; then
  ditto "$APP_SOURCE" "$DEST_PATH"
else
  sudo ditto "$APP_SOURCE" "$DEST_PATH"
fi

echo "Done. App installed at: $DEST_PATH"
