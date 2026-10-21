#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$TASK_ROOT/scripts/build-app.sh"
TASK_APP="$TASK_ROOT/dist/Anki Capture.app"
TASK_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$TASK_APP/Contents/Info.plist")
TASK_ARCHIVE="AnkiCapture-$TASK_VERSION-macOS-$(uname -m).zip"
cd "$TASK_ROOT/dist"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$TASK_APP" "$TASK_ARCHIVE"
/usr/bin/shasum -a 256 "$TASK_ARCHIVE" > "$TASK_ARCHIVE.sha256"
print -r -- "$TASK_ROOT/dist/$TASK_ARCHIVE"
