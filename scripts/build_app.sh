#!/bin/bash
# Compile Disk Cleaner (binaire universel), assemble le .app, signe ad hoc et crée le .dmg.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  VERSION="$(git describe --tags --abbrev=0 2>/dev/null || echo 1.0.0)"
fi
VERSION="${VERSION#v}"
APP_NAME="Disk Cleaner"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "==> Build release $VERSION"
if swift build -c release --arch arm64 --arch x86_64; then
  BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
  echo "Universal build failed, falling back to native architecture" >&2
  swift build -c release
  BIN_DIR="$(swift build -c release --show-bin-path)"
fi

echo "==> Assemble $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DiskCleaner" "$APP/Contents/MacOS/DiskCleaner"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
scripts/make_icon.sh "$APP/Contents/Resources/AppIcon.icns"
plutil -lint "$APP/Contents/Info.plist"
lipo -info "$APP/Contents/MacOS/DiskCleaner"

echo "==> Ad-hoc codesign"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

echo "==> DMG"
STAGING="build/dmg-staging"
rm -rf "$STAGING"; mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
DMG="$DIST/DiskCleaner-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
echo "DMG: $DMG"
