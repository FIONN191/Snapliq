#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(python3 -c 'import json; print(json.load(open("brand/product.json"))["version"])')"
APP="outputs/builds/$VERSION/Snapliq.app"
codesign --verify --deep --strict "$APP"
STAGE="$(mktemp -d "${TMPDIR:-/tmp/}snapliq-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Snapliq.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/使用说明.txt" <<'EOF'
Snapliq — 截图与录屏工具

将 Snapliq.app 拖入 Applications，或先退出当前 Snapliq 后从开发目录直接打开。
首次截图按系统提示授予屏幕录制权限；麦克风仅在选中录制麦克风时请求。
macOS 菜单栏 → 区域截图 / 屏幕录制 / 设置。关闭设置后继续常驻。
Command + X 会占用普通剪切键；在设置中明确接受冲突或录入其他快捷键。
区域录屏：屏幕录制 → 框选录制区域 → Enter → 选择保存文件并开始。
本版区域录屏限一个显示器。全程无需 Chrome 或扩展。

此包为 Apple Silicon、macOS 14+ 开发版，临时签名，尚未 Developer ID 签名公证。
不要同时运行多份 Snapliq；开发版更新或移动后，系统可能要求重新授权。
EOF
hdiutil create -volname "Snapliq $VERSION" -srcfolder "$STAGE" -ov -format UDZO "outputs/Snapliq-$VERSION-macOS-arm64-development.dmg"
hdiutil verify "outputs/Snapliq-$VERSION-macOS-arm64-development.dmg"
