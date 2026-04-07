#!/bin/bash

# Installer
# Usage: curl -sL <raw-install-script-url> | bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/release.config.sh" ]; then
    source "${SCRIPT_DIR}/release.config.sh"
else
    APP_NAME="${APP_NAME:-Kalam}"
    RELEASE_ZIP_NAME="${RELEASE_ZIP_NAME:-Kalam.zip}"
    DOWNLOAD_URL="${DOWNLOAD_URL:-https://github.com/harshvardhaniimi/kalam/releases/latest/download/${RELEASE_ZIP_NAME}}"
    HOTKEY_DISPLAY="${HOTKEY_DISPLAY:-Cmd+Shift+Space}"
fi

INSTALL_DIR="/Applications"
TMP_DIR=$(mktemp -d)
ZIP_PATH="${TMP_DIR}/${RELEASE_ZIP_NAME}"

echo "Installing $APP_NAME..."
echo ""

# Download
echo "Downloading..."
curl -fL "$DOWNLOAD_URL" -o "$ZIP_PATH"

# Unzip
echo "Extracting..."
unzip -q "$ZIP_PATH" -d "$TMP_DIR"

APP_BUNDLE_PATH="${TMP_DIR}/${APP_NAME}.app"
if [ ! -d "$APP_BUNDLE_PATH" ]; then
    APP_BUNDLE_PATH="$(find "$TMP_DIR" -maxdepth 3 -type d -name "*.app" | head -n 1)"
fi

if [ -z "$APP_BUNDLE_PATH" ] || [ ! -d "$APP_BUNDLE_PATH" ]; then
    echo "❌ Could not find an app bundle in downloaded archive."
    rm -rf "$TMP_DIR"
    exit 1
fi

# Check if we can write to /Applications, otherwise use ~/Applications
if [ ! -w "$INSTALL_DIR" ]; then
    INSTALL_DIR="$HOME/Applications"
    mkdir -p "$INSTALL_DIR"
    echo "Using $INSTALL_DIR (no admin privileges)"
fi

# Remove old version if exists
if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    echo "Removing previous version..."
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi

# Move to Applications
echo "Installing to $INSTALL_DIR..."
mv "$APP_BUNDLE_PATH" "$INSTALL_DIR/${APP_NAME}.app"

# Remove quarantine attribute
echo "Removing quarantine..."
xattr -cr "$INSTALL_DIR/$APP_NAME.app"

# Cleanup
rm -rf "$TMP_DIR"

echo ""
echo "Installed successfully!"
echo ""
echo "To launch: open $INSTALL_DIR/$APP_NAME.app"
echo ""
echo "First launch setup:"
echo "  1. Right-click the app and select 'Open' (first time only)"
echo "  2. Grant Accessibility permission in System Settings"
echo "  3. Grant Microphone access when prompted"
echo "  4. Press ${HOTKEY_DISPLAY} anywhere to start recording!"
echo ""
