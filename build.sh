#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
BUILD_DIR="$PROJECT_DIR/build"
APP="$BUILD_DIR/RocketToggle.app"
CONTENTS="$APP/Contents"
ARCH="$(uname -m)"
MIN_OS="13.0"
WORK="${TMPDIR:-/tmp}/rockettoggle-build-$$"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$WORK"

swiftc \
  -Osize \
  -whole-module-optimization \
  -target "${ARCH}-apple-macosx${MIN_OS}" \
  -module-cache-path "$WORK/mcp" \
  -framework AppKit \
  -framework CoreText \
  "$PROJECT_DIR/Sources/main.swift" \
  -o "$CONTENTS/MacOS/RocketToggle"

strip -x "$CONTENTS/MacOS/RocketToggle"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS/Info.plist"

plutil -lint "$CONTENTS/Info.plist" >/dev/null
xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - --timestamp=none --identifier "app.local.rockettoggle" "$APP"

echo "── build ok ──"
echo "app: $APP"
du -sh "$APP"
echo -n "bin: "
wc -c < "$CONTENTS/MacOS/RocketToggle" | awk '{printf "%.1f KB\n", $1/1024}'
