#!/bin/bash

# Installer
# Usage: curl -sL <raw-install-script-url> | bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/release.config.sh" ]; then
    source "${SCRIPT_DIR}/release.config.sh"
else
    APP_NAME="${APP_NAME:-Kalam}"
    EXECUTABLE_NAME="${EXECUTABLE_NAME:-Kalam}"
    BUNDLE_ID="${BUNDLE_ID:-io.kalam.app}"
    RELEASE_ZIP_NAME="${RELEASE_ZIP_NAME:-Kalam.zip}"
    DOWNLOAD_URL="${DOWNLOAD_URL:-https://github.com/harshvardhaniimi/kalam/releases/latest/download/${RELEASE_ZIP_NAME}}"
    HOTKEY_DISPLAY="${HOTKEY_DISPLAY:-Cmd+Shift+Space}"
fi

SYSTEM_INSTALL_DIR="/Applications"
USER_INSTALL_DIR="${HOME}/Applications"
BACKUP_ROOT="${BACKUP_ROOT:-${HOME}/Desktop/deleted by clwd/Kalam installer backups}"
TMP_DIR=$(mktemp -d)
ZIP_PATH="${TMP_DIR}/${RELEASE_ZIP_NAME}"

cleanup() {
    if [ "${INSTALL_IN_PROGRESS:-0}" = "1" ] \
       && [ -n "${TARGET_APP_PATH:-}" ] \
       && [ ! -d "$TARGET_APP_PATH" ] \
       && [ -n "${BACKUP_APP_PATH:-}" ] \
       && [ -d "$BACKUP_APP_PATH" ]; then
        echo "Update interrupted. Restoring the previous version..."
        run_with_install_permissions mv "$BACKUP_APP_PATH" "$TARGET_APP_PATH" || true
    fi
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

read_app_version() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$1/Contents/Info.plist" 2>/dev/null || true
}

run_with_install_permissions() {
    if [ "${USE_SUDO:-0}" = "1" ]; then
        sudo "$@"
    else
        "$@"
    fi
}

echo "Checking the latest $APP_NAME release..."
echo ""

# Download
echo "Downloading..."
curl --fail --location --retry 3 --retry-delay 1 "$DOWNLOAD_URL" -o "$ZIP_PATH"

# Unzip
echo "Extracting..."
unzip -q "$ZIP_PATH" -d "$TMP_DIR"

APP_BUNDLE_PATH="${TMP_DIR}/${APP_NAME}.app"
if [ ! -d "$APP_BUNDLE_PATH" ]; then
    APP_BUNDLE_PATH="$(find "$TMP_DIR" -maxdepth 3 -type d -name "*.app" | head -n 1)"
fi

if [ -z "$APP_BUNDLE_PATH" ] || [ ! -d "$APP_BUNDLE_PATH" ]; then
    echo "❌ Could not find an app bundle in downloaded archive."
    exit 1
fi

# Validate the release before touching an existing installation.
NEW_VERSION=$(read_app_version "$APP_BUNDLE_PATH")
if [ -z "$NEW_VERSION" ]; then
    echo "❌ The downloaded app does not contain a valid version number."
    exit 1
fi
if ! codesign --verify --deep --strict "$APP_BUNDLE_PATH" 2>/dev/null; then
    echo "❌ The downloaded app failed macOS code-signature verification."
    exit 1
fi

# Update the location where Kalam is already installed.
if [ -z "${INSTALL_DIR:-}" ]; then
    if [ -d "$SYSTEM_INSTALL_DIR/${APP_NAME}.app" ]; then
        INSTALL_DIR="$SYSTEM_INSTALL_DIR"
    elif [ -d "$USER_INSTALL_DIR/${APP_NAME}.app" ]; then
        INSTALL_DIR="$USER_INSTALL_DIR"
    elif [ -w "$SYSTEM_INSTALL_DIR" ]; then
        INSTALL_DIR="$SYSTEM_INSTALL_DIR"
    else
        INSTALL_DIR="$USER_INSTALL_DIR"
    fi
fi
mkdir -p "$INSTALL_DIR"

TARGET_APP_PATH="$INSTALL_DIR/${APP_NAME}.app"
CURRENT_VERSION=""
if [ -d "$TARGET_APP_PATH" ]; then
    CURRENT_VERSION=$(read_app_version "$TARGET_APP_PATH")
fi

if [ -n "$CURRENT_VERSION" ] && [ "$CURRENT_VERSION" = "$NEW_VERSION" ]; then
    echo ""
    echo "$APP_NAME $CURRENT_VERSION is already the latest release."
    exit 0
fi

USE_SUDO=0
if [ ! -w "$INSTALL_DIR" ]; then
    if [ "$INSTALL_DIR" = "$SYSTEM_INSTALL_DIR" ]; then
        echo "Administrator permission is required to update $TARGET_APP_PATH."
        sudo -v
        USE_SUDO=1
    else
        echo "❌ Cannot write to $INSTALL_DIR."
        exit 1
    fi
fi

if [ -d "$TARGET_APP_PATH" ] && [ "${SKIP_APP_QUIT:-0}" != "1" ]; then
    echo "Quitting the installed copy of $APP_NAME..."
    osascript -e "tell application id \"${BUNDLE_ID}\" to quit" 2>/dev/null || true
    for _ in {1..20}; do
        if ! pgrep -x "$EXECUTABLE_NAME" >/dev/null 2>&1; then
            break
        fi
        sleep 0.25
    done
    if pgrep -x "$EXECUTABLE_NAME" >/dev/null 2>&1; then
        echo "❌ $APP_NAME is still running. Quit it, then run this installer again."
        exit 1
    fi
fi

BACKUP_APP_PATH=""
if [ -d "$TARGET_APP_PATH" ]; then
    SAFE_CURRENT_VERSION="${CURRENT_VERSION:-unknown}"
    BACKUP_DIR="$BACKUP_ROOT/$(date +%Y-%m-%d_%H-%M-%S)-$$"
    BACKUP_APP_PATH="$BACKUP_DIR/${APP_NAME}-${SAFE_CURRENT_VERSION}.app"
    mkdir -p "$BACKUP_DIR"
    echo "Preserving version ${SAFE_CURRENT_VERSION} at $BACKUP_APP_PATH..."
    INSTALL_IN_PROGRESS=1
    run_with_install_permissions mv "$TARGET_APP_PATH" "$BACKUP_APP_PATH"
    if [ "$USE_SUDO" = "1" ]; then
        sudo chown -R "$(id -u):$(id -g)" "$BACKUP_DIR" || echo "Warning: the backup may require administrator permission to restore manually."
    fi
fi

# Move the validated release into place, restoring the prior version on failure.
if [ -n "$CURRENT_VERSION" ]; then
    echo "Updating $APP_NAME $CURRENT_VERSION → $NEW_VERSION..."
else
    echo "Installing $APP_NAME $NEW_VERSION..."
fi
if ! run_with_install_permissions mv "$APP_BUNDLE_PATH" "$TARGET_APP_PATH"; then
    echo "❌ Installation failed."
    if [ -n "$BACKUP_APP_PATH" ] && [ -d "$BACKUP_APP_PATH" ]; then
        echo "Restoring the previous version..."
        run_with_install_permissions mv "$BACKUP_APP_PATH" "$TARGET_APP_PATH"
    fi
    INSTALL_IN_PROGRESS=0
    exit 1
fi
INSTALL_IN_PROGRESS=0

# Remove quarantine attribute
echo "Removing quarantine..."
run_with_install_permissions xattr -cr "$TARGET_APP_PATH" || echo "Warning: macOS quarantine metadata could not be cleared automatically."

echo ""
if [ -n "$CURRENT_VERSION" ]; then
    echo "Updated successfully to $APP_NAME $NEW_VERSION!"
    echo "Your settings, models, and transcription history were preserved."
else
    echo "Installed successfully!"
fi
echo ""
echo "To launch: open \"$TARGET_APP_PATH\""
echo ""
if [ -z "$CURRENT_VERSION" ]; then
    echo "First launch setup:"
    echo "  1. Right-click the app and select 'Open' (first time only)"
    echo "  2. Grant Accessibility permission in System Settings"
    echo "  3. Grant Microphone access when prompted"
    echo "  4. Press ${HOTKEY_DISPLAY} anywhere to start recording!"
    echo ""
fi
