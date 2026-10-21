#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -gt 1 || ( $# -eq 1 && "${1:-}" != --native && "${1:-}" != --universal ) ]]; then
    print -u2 'Usage: scripts/package-release.sh [--universal | --native]'
    exit 2
fi
if [[ "${1:-}" == --native ]]; then
    "$TASK_ROOT/scripts/build-app.sh"
else
    "$TASK_ROOT/scripts/build-app.sh" --universal
fi
TASK_APP="$TASK_ROOT/dist/Anki Capture.app"
TASK_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$TASK_APP/Contents/Info.plist")
TASK_ARCHS="$(lipo -archs "$TASK_APP/Contents/MacOS/AnkiCapture")"
case "$TASK_ARCHS" in
    *arm64*x86_64*|*x86_64*arm64*) TASK_PLATFORM=universal ;;
    arm64|x86_64) TASK_PLATFORM="$TASK_ARCHS" ;;
    *) print -u2 "Unsupported executable architectures: $TASK_ARCHS"; exit 1 ;;
esac
TASK_BASENAME="AnkiCapture-$TASK_VERSION-macOS-$TASK_PLATFORM"
TASK_ARCHIVE="$TASK_BASENAME.zip"
TASK_IMAGE="$TASK_BASENAME.dmg"
cd "$TASK_ROOT/dist"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$TASK_APP" "$TASK_ARCHIVE"
TASK_STAGE="$(mktemp -d "$TASK_ROOT/dist/dmg-stage.XXXXXX")"
trap 'rm -rf "$TASK_STAGE"' EXIT
ditto "$TASK_APP" "$TASK_STAGE/Anki Capture.app"
ln -s /Applications "$TASK_STAGE/Applications"
cat > "$TASK_STAGE/Install - 安装.txt" <<'INSTALL'
Anki Capture — Install / 安装

ENGLISH
1. Drag Anki Capture.app to Applications, then eject this disk image.
2. Open Anki Capture from Applications. No Xcode or build tools are needed.
3. Install Anki Desktop and AnkiConnect (add-on code: 2055492159), then restart Anki.
4. Install at least one supported official AI CLI: Codex, Claude Code, or Gemini.
   In AI Connections, connect your own account and choose a model.
5. In Preferences, confirm your explanation language and select or create a deck.
6. Grant Accessibility access to Anki Capture when prompted. Select text in a
   reader and press Control + Option + Command + A, or enter text manually.

This is a development preview, not Apple-notarized. If macOS blocks the first
launch, and you trust this release, open System Settings > Privacy & Security
after trying to launch it, then choose Open Anyway for Anki Capture.
Apple's explanation: https://support.apple.com/en-us/102445
Do not disable Gatekeeper system-wide.

Requires macOS 14 or later. Downloads named 'universal' contain Apple Silicon
and Intel executables; Apple Silicon is tested, Intel hardware is not yet tested.
AI requests use your provider account, quota and billing, and normally require
the internet. Anki Desktop, AnkiConnect and AI CLIs are not bundled.

简体中文
1. 将 Anki Capture.app 拖到 Applications（应用程序），然后推出此磁盘映像。
2. 从“应用程序”打开 Anki Capture，无需 Xcode 或编译工具。
3. 安装 Anki 桌面版和 AnkiConnect（插件代码：2055492159），然后重启 Anki。
4. 安装至少一种支持的官方 AI CLI：Codex、Claude Code 或 Gemini。
   在“AI 连接”中连接自己的账号并选择模型。
5. 在“偏好设置”中确认释义语言，并选择或新建牌组。
6. 按提示授予 Anki Capture 辅助功能权限。在阅读器中选中文本，
   按 Control + Option + Command + A 收录，也可以手动输入。

当前为开发预览版，尚未经过 Apple 公证。如果首次启动被 macOS 阻止，
请确认信任此发行来源，再前往“系统设置 > 隐私与安全性”为该应用选择“仍要打开”。
Apple 官方说明：https://support.apple.com/zh-cn/102445
无需全局关闭 Gatekeeper。

需要 macOS 14 或更新版本。文件名含 universal 的构建包含 Apple Silicon 和 Intel 可执行文件；
Apple Silicon 已验证，Intel 尚未经真机验证。AI 调用使用自己的服务商账号、
额度与计费，通常需要联网。安装包不包含 Anki、AnkiConnect 或 AI CLI。

Project / 项目：https://github.com/nohairblingbling/anki-capture
Feedback / 反馈：https://github.com/nohairblingbling/anki-capture/issues
INSTALL
hdiutil create -volname 'Anki Capture' -fs HFS+ -srcfolder "$TASK_STAGE" -format UDZO -ov "$TASK_IMAGE"
hdiutil verify "$TASK_IMAGE"
/usr/bin/shasum -a 256 "$TASK_ARCHIVE" > "$TASK_ARCHIVE.sha256"
/usr/bin/shasum -a 256 "$TASK_IMAGE" > "$TASK_IMAGE.sha256"
/usr/bin/shasum -a 256 "$TASK_ARCHIVE" "$TASK_IMAGE" > "$TASK_BASENAME-SHA256SUMS.txt"
print -r -- "$TASK_ROOT/dist/$TASK_IMAGE"
print -r -- "$TASK_ROOT/dist/$TASK_ARCHIVE"
