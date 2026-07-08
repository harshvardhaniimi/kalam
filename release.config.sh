#!/bin/bash

# Central release + branding configuration.
# Edit this file first when rebranding the app.

# Product identity
APP_NAME="${APP_NAME:-Kalam}"
EXECUTABLE_NAME="${EXECUTABLE_NAME:-Kalam}"
BUNDLE_ID="${BUNDLE_ID:-io.kalam.app}"
APP_SUPPORT_SUBDIR="${APP_SUPPORT_SUBDIR:-Kalam}"
MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-14.0}"
DEFAULT_VERSION="${DEFAULT_VERSION:-2.6.0}"

# Distribution links
REPO_OWNER="${REPO_OWNER:-harshvardhaniimi}"
REPO_NAME="${REPO_NAME:-kalam}"
RELEASE_ZIP_NAME="${RELEASE_ZIP_NAME:-${APP_NAME}.zip}"
DOWNLOAD_URL="${DOWNLOAD_URL:-https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/latest/download/${RELEASE_ZIP_NAME}}"
FEEDBACK_URL="${FEEDBACK_URL:-https://github.com/${REPO_OWNER}/${REPO_NAME}/issues}"

# User-facing copy
HOTKEY_DISPLAY="${HOTKEY_DISPLAY:-Cmd+Shift+Space}"
MICROPHONE_USAGE_DESCRIPTION="${MICROPHONE_USAGE_DESCRIPTION:-${APP_NAME} needs access to your microphone to transcribe speech.}"
SPEECH_USAGE_DESCRIPTION="${SPEECH_USAGE_DESCRIPTION:-${APP_NAME} uses speech recognition to convert your voice to text.}"
APPLE_EVENTS_USAGE_DESCRIPTION="${APPLE_EVENTS_USAGE_DESCRIPTION:-${APP_NAME} needs to send keystrokes to insert transcribed text at your cursor position.}"
ACCESSIBILITY_USAGE_DESCRIPTION="${ACCESSIBILITY_USAGE_DESCRIPTION:-${APP_NAME} needs accessibility access to detect global hotkeys and insert text at your cursor.}"
NOTIFICATIONS_USAGE_DESCRIPTION="${NOTIFICATIONS_USAGE_DESCRIPTION:-${APP_NAME} sends notifications when recording starts, stops, and transcription is complete.}"
COPYRIGHT_TEXT="${COPYRIGHT_TEXT:-Copyright © 2026. All rights reserved.}"
