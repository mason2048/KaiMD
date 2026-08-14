#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="KaiMD"
OUTPUT_DIR="$ROOT/outputs"
APP="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"
ARM_BUILD="$ROOT/work/build-arm64"
X86_BUILD="$ROOT/work/build-x86_64"
ICON_SOURCE="$ROOT/Assets/AppIcon.png"

mkdir -p "$OUTPUT_DIR" "$ROOT/work"
rm -rf "$APP"

swift build --package-path "$ROOT" --scratch-path "$ARM_BUILD" --triple arm64-apple-macosx14.0 -c release
swift build --package-path "$ROOT" --scratch-path "$X86_BUILD" --triple x86_64-apple-macosx14.0 -c release

ARM_BIN="$(swift build --package-path "$ROOT" --scratch-path "$ARM_BUILD" --triple arm64-apple-macosx14.0 -c release --show-bin-path)"
X86_BIN="$(swift build --package-path "$ROOT" --scratch-path "$X86_BUILD" --triple x86_64-apple-macosx14.0 -c release --show-bin-path)"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
lipo -create "$ARM_BIN/$APP_NAME" "$X86_BIN/$APP_NAME" -output "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT/scripts/Info.plist" "$CONTENTS/Info.plist"

RESOURCE_BUNDLE="${APP_NAME}_${APP_NAME}.bundle"
if [[ -d "$ARM_BIN/$RESOURCE_BUNDLE" ]]; then
    cp -R "$ARM_BIN/$RESOURCE_BUNDLE" "$CONTENTS/Resources/$RESOURCE_BUNDLE"
fi

ICONSET="$ROOT/work/AppIcon.iconset"
rm -rf "$ICONSET"
swift "$ROOT/scripts/generate_icon.swift" "$ICON_SOURCE" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

plutil -lint "$CONTENTS/Info.plist"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
file "$CONTENTS/MacOS/$APP_NAME"
echo "$APP"
