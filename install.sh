#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
"$ROOT/build.sh"

DEST_DIR="$HOME/Applications"
APP_SRC="$ROOT/build/RocketToggle.app"
APP_DST="$DEST_DIR/RocketToggle.app"
LABEL="app.local.rockettoggle"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"

pkill -x RocketToggle 2>/dev/null || true
sleep 0.2

mkdir -p "$DEST_DIR" "$HOME/Library/LaunchAgents"
rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"
xattr -cr "$APP_DST" 2>/dev/null || true
codesign --force --sign - --timestamp=none --identifier "$LABEL" "$APP_DST" 2>/dev/null || true

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${LABEL}</string>
	<key>ProgramArguments</key>
	<array>
		<string>${APP_DST}/Contents/MacOS/RocketToggle</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<false/>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load "$PLIST" 2>/dev/null || true

sleep 0.3
if ! pgrep -x RocketToggle >/dev/null 2>&1; then
  open -a "$APP_DST"
fi

echo "✓ 已安装: $APP_DST"
echo "✓ 登录自启"
echo "  左键连接/断开小火箭 · 右键菜单"
