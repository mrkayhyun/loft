#!/usr/bin/env bash
# Build Burrow.app: Rust engine + SwiftUI app + icon, ad-hoc signed.
# Usage: scripts/build-app.sh            → dist/Burrow.app
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Burrow.app"
WORK="$DIST/.work"
VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' "$ROOT/engine/Cargo.toml" | head -1)"
BUNDLE_ID="dev.burrow.app"
MIN_MACOS="15.0"

step() { printf '\033[1;35m▸\033[0m %s\n' "$*"; }

step "Building engine (release)"
cargo build --release --manifest-path "$ROOT/engine/Cargo.toml"

step "Building app (release)"
swift build -c release --package-path "$ROOT/app"
APP_BIN="$(swift build -c release --package-path "$ROOT/app" --show-bin-path)/Burrow"

step "Checking translations"
"$ROOT/scripts/check-l10n.sh"

step "Rendering icon"
rm -rf "$WORK" && mkdir -p "$WORK/AppIcon.iconset"
swift "$ROOT/scripts/make-icon.swift" "$WORK/icon-1024.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$WORK/icon-1024.png" --out "$WORK/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$WORK/icon-1024.png" --out "$WORK/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/AppIcon.iconset" -o "$WORK/AppIcon.icns"

step "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$APP_BIN" "$APP/Contents/MacOS/Burrow"
cp "$ROOT/engine/target/release/burrow" "$APP/Contents/Resources/burrow"
cp "$WORK/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
for lproj in "$ROOT/app/Localization"/*.lproj; do
    dest="$APP/Contents/Resources/$(basename "$lproj")"
    mkdir -p "$dest"
    for table in "$lproj"/*.strings; do
        plutil -convert binary1 -o "$dest/$(basename "$table")" "$table"
    done
done
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Burrow</string>
    <key>CFBundleDisplayName</key><string>Burrow</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>Burrow</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>ko</string></array>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>GPL-3.0. Engine derived from tw93/mole.</string>
</dict>
</plist>
PLIST

step "Signing (ad-hoc)"
codesign --force --sign - "$APP/Contents/Resources/burrow"
codesign --force --sign - "$APP"
rm -rf "$WORK"

step "Done → $APP"
