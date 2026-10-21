#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_SOURCE="$TASK_ROOT/dist/Anki Capture.app"
TASK_TARGET="$HOME/Applications/Anki Capture.app"
TASK_CLI="$HOME/.local/bin/anki-capture"
if [[ ! -d "$TASK_SOURCE" ]]; then "$TASK_ROOT/scripts/build-app.sh"; fi
if [[ -e "$TASK_TARGET" ]]; then
    TASK_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$TASK_TARGET/Contents/Info.plist")
    [[ "$TASK_ID" == dev.ankicapture.app ]] || { print -u2 "目标位置已有其他应用，已停止。"; exit 1; }
fi
if [[ -e "$TASK_CLI" && ! -L "$TASK_CLI" ]]; then print -u2 "CLI 位置已有其他文件，已停止。"; exit 1; fi
mkdir -p "$HOME/Applications" "$HOME/.local/bin"
ditto "$TASK_SOURCE" "$TASK_TARGET"
ln -sfn "$TASK_TARGET/Contents/MacOS/anki-capture" "$TASK_CLI"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$TASK_TARGET"
print -r -- "$TASK_TARGET"
