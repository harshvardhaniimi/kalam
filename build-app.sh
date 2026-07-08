#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/release.config.sh"
cd "${SCRIPT_DIR}"

VERSION="${1:-${DEFAULT_VERSION}}"

# Build the app
echo "🔨 Building ${APP_NAME} v${VERSION}..."
swift build -c release

# Create app bundle structure
APP_DIR="$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Clean up old bundle
rm -rf "$APP_DIR"

# Create directory structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Generate app icon
echo "🎨 Generating app icon..."
swift "${SCRIPT_DIR}/scripts/generate-icon.swift" "$RESOURCES_DIR"

# Copy executable
cp ".build/release/${EXECUTABLE_NAME}" "$MACOS_DIR/${EXECUTABLE_NAME}"

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS_VERSION}</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>${MICROPHONE_USAGE_DESCRIPTION}</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>${SPEECH_USAGE_DESCRIPTION}</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>${APPLE_EVENTS_USAGE_DESCRIPTION}</string>
    <key>NSSystemAdministrationUsageDescription</key>
    <string>${ACCESSIBILITY_USAGE_DESCRIPTION}</string>
    <key>NSUserNotificationUsageDescription</key>
    <string>${NOTIFICATIONS_USAGE_DESCRIPTION}</string>
    <key>NSHumanReadableCopyright</key>
    <string>${COPYRIGHT_TEXT}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Code sign the app.
# A STABLE identity is required for macOS permissions (Accessibility,
# Microphone) to survive rebuilds — ad-hoc signatures change every build
# and silently invalidate the TCC grants. See signing/README.md.
if [ -z "${CODESIGN_IDENTITY:-}" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "Kalam Dev Signing"; then
    CODESIGN_IDENTITY="Kalam Dev Signing"
fi

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    echo "🔏 Code signing with identity: ${CODESIGN_IDENTITY}"
    # Hardened runtime (--options runtime) blocks microphone access unless the
    # audio-input entitlement is present — never sign without it.
    codesign --force --deep --options runtime \
        --entitlements "${SCRIPT_DIR}/Kalam-direct.entitlements" \
        --sign "${CODESIGN_IDENTITY}" "$APP_DIR"
else
    echo "⚠️  No stable signing identity — falling back to AD-HOC signing."
    echo "   Accessibility/Microphone grants will break on every rebuild."
    echo "   One-time fix: see signing/README.md"
    codesign --force --deep --sign - "$APP_DIR"
fi

echo ""
echo "✅ App bundle created: $APP_DIR"
echo "   To run: open $APP_DIR"
