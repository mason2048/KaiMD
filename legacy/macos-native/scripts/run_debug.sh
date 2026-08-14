#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/outputs/KaiMD-debug.app"
ICON_SOURCE="$ROOT/Assets/AppIcon.png"

# Ensure `open` cannot reconnect to an older debug process after the bundle is
# replaced. Ask the app to persist its session first, then use a targeted
# fallback only if it did not terminate promptly.
if pgrep -f "$APP/Contents/MacOS/KaiMD" >/dev/null 2>&1; then
    osascript -e 'tell application id "com.local.kaimd" to quit' >/dev/null 2>&1 || true
    for _ in {1..20}; do
        pgrep -f "$APP/Contents/MacOS/KaiMD" >/dev/null 2>&1 || break
        sleep 0.1
    done
    pkill -f "$APP/Contents/MacOS/KaiMD" >/dev/null 2>&1 || true
fi

swift build --package-path "$ROOT" -c debug
BIN_DIR="$(swift build --package-path "$ROOT" -c debug --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/KaiMD" "$APP/Contents/MacOS/KaiMD"
cp "$ROOT/scripts/Info.plist" "$APP/Contents/Info.plist"

RESOURCE_BUNDLE="KaiMD_KaiMD.bundle"
if [[ -d "$BIN_DIR/$RESOURCE_BUNDLE" ]]; then
    cp -R "$BIN_DIR/$RESOURCE_BUNDLE" "$APP/Contents/Resources/$RESOURCE_BUNDLE"
fi

ICONSET="$ROOT/work/AppIcon.iconset"
rm -rf "$ICONSET"
swift "$ROOT/scripts/generate_icon.swift" "$ICON_SOURCE" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
if [[ "${KAIMD_SKIP_LAUNCH:-0}" != "1" ]]; then
    open -n "$APP"
fi
