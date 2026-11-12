#!/bin/zsh
# Builds GitOS.app into ./build (and optionally installs to /Applications with --install).
set -euo pipefail
cd "$(dirname "$0")/.."

# The release version. Sparkle compares this, so raise it for every release (scripts/release.sh does).
VERSION="0.2.1"
# Sparkle only installs updates signed with the matching private key, kept in the login Keychain
# under the account "gitos" (back it up: generate_keys --account gitos -x <file>).
SPARKLE_PUBLIC_KEY="vecXhaUoRcEc19rFlXLvb6hyeN3Q0PrwQy/k3GOZcRU="

swift build -c release --product GitOS
BIN="$(swift build -c release --show-bin-path)/GitOS"
APP="build/GitOS.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GitOS"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Compiled so sidebar and list selection use the GitOS teal; SwiftUI's .tint doesn't reach them.
xcrun actool Resources/Assets.xcassets --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target 27.0 --output-format human-readable-text \
    --output-partial-info-plist /dev/null >/dev/null
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>GitOS</string>
    <key>CFBundleDisplayName</key><string>GitOS</string>
    <key>CFBundleIdentifier</key><string>com.angelsaikia.gitos</string>
    <key>CFBundleExecutable</key><string>GitOS</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSAccentColorName</key><string>AccentColor</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>SUFeedURL</key><string>https://github.com/Dhunu/gitOS/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUScheduledCheckInterval</key><integer>3600</integer>
    <key>LSMinimumSystemVersion</key><string>27.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Folder</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>None</string>
            <key>LSItemContentTypes</key><array><string>public.folder</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST
ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/GitOS"
# A stable certificate keeps the app's identity the same across builds, so the Keychain doesn't
# ask for the token password again after every update. Falls back to ad-hoc (e.g. CI, contributors).
IDENTITY="${SIGN_IDENTITY:-Apple Development: angelsaikia333@gmail.com (23445DDSB9)}"
security find-identity -v -p codesigning | grep -qF "\"$IDENTITY\"" || IDENTITY=-
codesign --force --deep --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework" >/dev/null
codesign --force --sign "$IDENTITY" "$APP" >/dev/null
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/GitOS.app
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/GitOS.app"
fi
