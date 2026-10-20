#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
APP_NAME="VP2xMac"
BUNDLE_ID="nl.rob.vp2xcontrol"
DIST_BUNDLE="$ROOT_DIR/dist/VP2x Control.app"
case "$MODE" in
  run|--verify|--debug|--logs|--telemetry) pkill -x "$APP_NAME" >/dev/null 2>&1 || true ;;
esac
# Compile a stable local copy: Documents may be managed by a File Provider.
BUILD_SOURCE="${TMPDIR:-/private/tmp}/vp2x-control-build-$UID"
APP_BUNDLE="$BUILD_SOURCE/VP2x Control.app"
mkdir -p "$BUILD_SOURCE"
/usr/bin/rsync -a --delete "$ROOT_DIR/Sources/" "$BUILD_SOURCE/Sources/"
/usr/bin/rsync -a --delete "$ROOT_DIR/Tests/" "$BUILD_SOURCE/Tests/"
cp "$ROOT_DIR/Package.swift" "$BUILD_SOURCE/Package.swift"
export CLANG_MODULE_CACHE_PATH="$BUILD_SOURCE/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_SOURCE/.build/ModuleCache"
if [[ "$MODE" == "--test" ]]; then
  swift run --package-path "$BUILD_SOURCE" --disable-sandbox VP2xChecks
  exit 0
fi
swift build --package-path "$BUILD_SOURCE" --disable-sandbox
BUILD_DIR="$(swift build --package-path "$BUILD_SOURCE" --show-bin-path)"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
/usr/bin/rsync -a "$BUILD_DIR/VP2xMac_VP2xCore.bundle/" "$APP_BUNDLE/Contents/Resources/"
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>VP2xMac</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>VP2x Control</string>
<key>CFBundleDisplayName</key><string>VP2x Control</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.11</string>
<key>CFBundleVersion</key><string>0.3.11</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSLocalNetworkUsageDescription</key><string>VP2x Control bedient jouw AirTools Voice Processor 2x via Ethernet.</string>
</dict></plist>
PLIST
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
mkdir -p "$ROOT_DIR/dist"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ROOT_DIR/dist/VP2x Control.zip"
rm -rf "$DIST_BUNDLE"
/usr/bin/ditto "$APP_BUNDLE" "$DIST_BUNDLE"
case "$MODE" in
  --build-only) ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 2; pgrep -x "$APP_NAME" >/dev/null ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "VP2xMac"' ;;
  --telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "nl.rob.vp2xcontrol"' ;;
  *) echo "usage: $0 [run|--build-only|--test|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
