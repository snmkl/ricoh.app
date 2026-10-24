#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: $0 [install]"
    echo "Build build/GRBrowser.app; install also copies it to ~/Applications."
}

if [ "$#" -gt 1 ]; then
    usage >&2
    exit 1
fi

install_app=false
case "${1:-}" in
    "") ;;
    install) install_app=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
esac

if [ "$(uname -s)" != Darwin ]; then
    echo "GRBrowser requires macOS and the Xcode Command Line Tools." >&2
    exit 1
fi

ROOT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_NAME=GRBrowser
APP_PATH="$BUILD_DIR/$APP_NAME.app"
MANIFEST="$ROOT_DIR/Info.plist"
plutil -lint "$MANIFEST"
mkdir -p "$BUILD_DIR"

# Stage the bundle so a compiler failure leaves the previous build intact.
STAGING_DIR="$(mktemp -d "$BUILD_DIR/.app-build.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
STAGED_APP="$STAGING_DIR/$APP_NAME.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"

python3 "$ROOT_DIR/swift-build.py" "$STAGED_APP/Contents/MacOS/$APP_NAME"

cp "$MANIFEST" "$STAGED_APP/Contents/Info.plist"

# Package standard and Retina icon sizes from the source artwork.
ICONSET="$STAGING_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ROOT_DIR/Assets/AppIcon.png" \
        --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" "$ROOT_DIR/Assets/AppIcon.png" \
        --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$STAGED_APP/Contents/Resources/AppIcon.icns"

plutil -lint "$STAGED_APP/Contents/Info.plist"
# Ad-hoc signing is sufficient for an app built and run on this Mac.
codesign --force --sign - "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"

rm -rf "$APP_PATH"
mv "$STAGED_APP" "$APP_PATH"
echo "Built: $APP_PATH"

if [ "$install_app" = true ]; then
    INSTALL_DIR="$HOME/Applications"
    mkdir -p "$INSTALL_DIR"
    # Refuse to replace an unrelated app with the same filename.
    if [ -e "$INSTALL_DIR/$APP_NAME.app" ]; then
        EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
            "$INSTALL_DIR/$APP_NAME.app/Contents/Info.plist" 2>/dev/null || true)"
        if [ "$EXISTING_ID" != local.GRBrowser ]; then
            echo "Refusing to replace an unrelated app: $INSTALL_DIR/$APP_NAME.app" >&2
            exit 1
        fi
    fi
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    ditto "$APP_PATH" "$INSTALL_DIR/$APP_NAME.app"
    echo "Installed: $INSTALL_DIR/$APP_NAME.app"
    echo "Open it from Finder or run: open \"$INSTALL_DIR/$APP_NAME.app\""
else
    echo "Open it from Finder or run: open \"$APP_PATH\""
fi
