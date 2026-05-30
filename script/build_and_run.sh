#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="SPPStudio"
BUNDLE_ID="com.sppstudio.debug"
PRODUCT_NAME="SwiftPlaygroundPlusPlusStudio"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/Apps/SwiftPlaygroundPlusPlusStudio"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

stop_existing() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -x "$PRODUCT_NAME" >/dev/null 2>&1 || true
}

build_product() {
  swift build --package-path "$PACKAGE_DIR"
}

stage_bundle() {
  local bin_path
  bin_path="$(swift build --package-path "$PACKAGE_DIR" --show-bin-path)/$PRODUCT_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$bin_path" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>SPPStudio</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>debug</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_running() {
  local attempts=0
  until pgrep -x "$APP_NAME" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 30 ]; then
      echo "SPPStudio did not launch as process '$APP_NAME'." >&2
      exit 1
    fi
    sleep 0.2
  done
}

case "$MODE" in
  run|--run)
    stop_existing
    build_product
    stage_bundle
    open_app
    ;;
  --verify|verify)
    stop_existing
    build_product
    stage_bundle
    open_app
    verify_running
    echo "Launched $APP_BUNDLE"
    ;;
  --debug|debug)
    stop_existing
    build_product
    stage_bundle
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    stop_existing
    build_product
    stage_bundle
    open_app
    verify_running
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    stop_existing
    build_product
    stage_bundle
    open_app
    verify_running
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --stop|stop)
    stop_existing
    ;;
  *)
    echo "usage: $0 [run|--verify|--debug|--logs|--telemetry|--stop]" >&2
    exit 2
    ;;
esac
