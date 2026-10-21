#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
TASK_ARCHITECTURES=("$(uname -m)")
if [[ $# -gt 1 || ( $# -eq 1 && "${1:-}" != --universal ) ]]; then
    print -u2 'Usage: scripts/build-app.sh [--universal]'
    exit 2
fi
if [[ "${1:-}" == --universal ]]; then
    TASK_ARCHITECTURES=(arm64 x86_64)
fi
TASK_BINARY_DIRS=()
for TASK_ARCH in "${TASK_ARCHITECTURES[@]}"; do
    swift build -c release --arch "$TASK_ARCH"
    TASK_BINARY_DIRS+=("$(swift build -c release --arch "$TASK_ARCH" --show-bin-path)")
done
TASK_APP="$TASK_ROOT/dist/Anki Capture.app"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
for TASK_PRODUCT in AnkiCapture anki-capture; do
    TASK_INPUTS=()
    for TASK_BIN in "${TASK_BINARY_DIRS[@]}"; do
        TASK_INPUTS+=("$TASK_BIN/$TASK_PRODUCT")
    done
    if [[ ${#TASK_INPUTS[@]} -gt 1 ]]; then
        lipo -create "${TASK_INPUTS[@]}" -output "$TASK_APP/Contents/MacOS/$TASK_PRODUCT"
    else
        cp "${TASK_INPUTS[1]}" "$TASK_APP/Contents/MacOS/$TASK_PRODUCT"
    fi
    chmod 755 "$TASK_APP/Contents/MacOS/$TASK_PRODUCT"
done
cp App/Info.plist "$TASK_APP/Contents/Info.plist"
for TASK_LOCALE in "$TASK_ROOT"/Sources/CaptureCore/Resources/*.lproj; do
    ditto "$TASK_LOCALE" "$TASK_APP/Contents/Resources/$(basename "$TASK_LOCALE")"
done
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
codesign --force --sign "$TASK_SIGNING_IDENTITY" --identifier dev.ankicapture.cli "$TASK_APP/Contents/MacOS/anki-capture"
codesign --force --sign "$TASK_SIGNING_IDENTITY" --identifier dev.ankicapture.app "$TASK_APP"
codesign --verify --strict "$TASK_APP/Contents/MacOS/anki-capture"
codesign --verify --deep --strict "$TASK_APP"
print -r -- "$TASK_APP"
