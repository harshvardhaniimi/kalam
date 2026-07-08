#!/bin/bash

# Create a release build of the app
# Usage: ./scripts/create-release.sh [version]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../release.config.sh"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

VERSION="${1:-${DEFAULT_VERSION}}"
BUILD_DIR=".build/release-${VERSION}"
ZIP_NAME_VERSIONED="${APP_NAME}-v${VERSION}.zip"
ZIP_NAME_LATEST="${RELEASE_ZIP_NAME}"

echo "🔨 Building ${APP_NAME} v${VERSION}..."

# Build release version
swift build -c release

# Create clean app bundle
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/${APP_NAME}.app/Contents/MacOS"
mkdir -p "${BUILD_DIR}/${APP_NAME}.app/Contents/Resources"

# Generate app icon
echo "🎨 Generating app icon..."
swift "${SCRIPT_DIR}/generate-icon.swift" "${BUILD_DIR}/${APP_NAME}.app/Contents/Resources"

# Copy executable
cp ".build/release/${EXECUTABLE_NAME}" "${BUILD_DIR}/${APP_NAME}.app/Contents/MacOS/${EXECUTABLE_NAME}"

# Create Info.plist with version
cat > "${BUILD_DIR}/${APP_NAME}.app/Contents/Info.plist" << PLIST
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
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Code sign the app (same rules as build-app.sh: stable identity when
# available, and hardened runtime REQUIRES the audio-input entitlement or
# microphone access fails silently)
if [ -z "${CODESIGN_IDENTITY:-}" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "Kalam Dev Signing"; then
    CODESIGN_IDENTITY="Kalam Dev Signing"
fi

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    echo "🔏 Code signing with identity: ${CODESIGN_IDENTITY}"
    codesign --force --deep --options runtime \
        --entitlements "${PROJECT_ROOT}/Kalam-direct.entitlements" \
        --sign "${CODESIGN_IDENTITY}" "${BUILD_DIR}/${APP_NAME}.app"
else
    echo "⚠️  No stable signing identity — falling back to AD-HOC signing."
    echo "   See signing/README.md"
    codesign --force --deep --sign - "${BUILD_DIR}/${APP_NAME}.app"
fi

# Create zips for distribution
echo "📦 Creating release zips..."
cd "${BUILD_DIR}"
zip -r "../../${ZIP_NAME_VERSIONED}" "${APP_NAME}.app"
zip -r "../../${ZIP_NAME_LATEST}" "${APP_NAME}.app"
cd ../..

echo ""
echo "✅ Release created successfully!"
echo ""
echo "   App:  ${BUILD_DIR}/${APP_NAME}.app"
echo "   Zips: ${ZIP_NAME_VERSIONED} (for archives)"
echo "         ${ZIP_NAME_LATEST} (for 'latest' download link)"
echo ""
echo "📝 Next steps:"
echo "   1. Test the app: open '${BUILD_DIR}/${APP_NAME}.app'"
echo "   2. Create GitHub release v${VERSION}"
echo "   3. Upload BOTH zip files to the release"
echo "   4. The docs page 'latest' link will automatically work"
echo ""
echo "⚠️  Users downloading from GitHub will need to:"
echo "   - Run: xattr -cr ~/Downloads/${APP_NAME}.app"
echo "   - Then right-click → Open (first time, to bypass Gatekeeper)"
echo "   - Grant Accessibility permissions in System Settings"
echo ""
echo "   (This is required because the app is not notarized with Apple)"
