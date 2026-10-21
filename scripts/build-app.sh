#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
swift build -c release
TASK_BIN="$(swift build -c release --show-bin-path)"
TASK_APP="$TASK_ROOT/dist/Anki Capture.app"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
cp "$TASK_BIN/AnkiCapture" "$TASK_APP/Contents/MacOS/AnkiCapture"
cp "$TASK_BIN/anki-capture" "$TASK_APP/Contents/MacOS/anki-capture"
cp App/Info.plist "$TASK_APP/Contents/Info.plist"
# Remove the resource bundle from the early prototype's retired shortcut dependency.
if [[ -d "$TASK_APP/KeyboardShortcuts_KeyboardShortcuts.bundle" ]]; then
    rm -rf "$TASK_APP/KeyboardShortcuts_KeyboardShortcuts.bundle"
fi
swift scripts/make-icon.swift "$TASK_ROOT/dist"
iconutil -c icns "$TASK_ROOT/dist/AppIcon.iconset" -o "$TASK_APP/Contents/Resources/AppIcon.icns"
TASK_SIGNING_IDENTITY="${ANKI_CAPTURE_SIGNING_IDENTITY:-}"
if [[ -z "$TASK_SIGNING_IDENTITY" && -f "$TASK_ROOT/.signing-identity" ]]; then
    IFS= read -r TASK_SIGNING_IDENTITY < "$TASK_ROOT/.signing-identity"
fi
TASK_SIGNING_IDENTITY="${TASK_SIGNING_IDENTITY:--}"
codesign --force --deep --sign "$TASK_SIGNING_IDENTITY" --identifier dev.ankicapture.app "$TASK_APP"
codesign --verify --deep --strict "$TASK_APP"
print -r -- "$TASK_APP"
