# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project Overview

Kalam is a native macOS menu bar app for speech-to-text dictation.
It has two transcription engines, selectable in Settings:

- **Local Whisper** via WhisperKit (CoreML) — offline, private. For Hindi use the Large Turbo model (`openai_whisper-large-v3-v20240930`); tiny/base/small are effectively English-only.
- **Sarvam AI** (cloud, `saaras:v3` via REST) — substantially better for Hindi/Hinglish (~half the WER of Whisper large-v3 on spontaneous Hindi). Needs an API key from dashboard.sarvam.ai; recordings are chunked to ≤25 s per request. Falls back to local Whisper automatically on any failure.

## Build Commands

```bash
# Build standalone .app bundle (recommended)
./build-app.sh [version]

# Run the app bundle
open Kalam.app

# Build from command line (debug)
swift build

# Build App Store variant (sandbox-compatible, no global hotkey/text insertion)
./build-appstore.sh
```

## Code Signing — IMPORTANT

Builds MUST be signed with the stable identity **"Kalam Dev Signing"** (login keychain); `build-app.sh` auto-detects it.
Never knowingly ship an ad-hoc build: macOS TCC ties Accessibility/Microphone grants to the signature, and ad-hoc signatures change every build, silently breaking paste-at-cursor.
Setup/recovery instructions: `signing/README.md`.

## Architecture

### App Entry Point
- `KalamApp.swift` — `AppDelegate` creates the menu bar status item and popover. Menu bar app (LSUIElement=true), no Dock icon.

### Central State
- `AppState.swift` — Singleton (`AppState.shared`). Coordinates services, holds published UI state, routes transcription through the selected engine (`performTranscription`). All user settings (model, language, engine, Sarvam key/mode, hotkey) persist to UserDefaults via didSet.

### Services (Sources/Kalam/Services/)
- `AudioCaptureService` — AVAudioEngine capture. Samples are accumulated **synchronously on the render thread** (SampleAccumulator, lock-guarded) — never hop actors in the tap callback, that loses the recording tail. Captures at the device's real sample rate and resamples to 16 kHz with AVAudioConverter at stop. Fires `onRecordingInterrupted` on AVAudioEngineConfigurationChange (device switch mid-recording).
- `AudioFileLoader` — validates dropped audio/media URLs and decodes, downmixes, and resamples them to 16 kHz mono for either engine. Dedicated audio uses AVAudioFile; MP4/QuickTime and other media containers fall back to AVAssetReader and contribute only their audio track.
- `WhisperService` — WhisperKit wrapper (load/transcribe). Despite the filename, this is WhisperKit, not whisper.cpp and not Apple Speech.
- `SarvamService` — Sarvam AI REST client (`POST /speech-to-text`, multipart, `api-subscription-key` header) + `TranscriptionEngine`/`SarvamMode` enums.
- `GlobalHotkeyManager` — Cmd+Shift+Space via Carbon RegisterEventHotKey (no Accessibility needed for the hotkey itself). Delivers both press and release; AppState turns them into tap-to-toggle vs hold-to-talk (release after ≥0.6 s stops and transcribes). Registration failure notifies the user. Disabled in App Store build.
- `KeychainHelper` — the Sarvam API key lives in the login keychain (never UserDefaults; a legacy plaintext value is auto-migrated on launch).
- `TextInsertionService` — clipboard + simulated Cmd+V. Checks `AXIsProcessTrusted()` first; if untrusted it notifies the user and leaves the text on the clipboard instead of failing silently. Clipboard-only in App Store build.
- `ModelManager` — downloads/locates WhisperKit CoreML models (HuggingFace cache layout under `~/Library/Application Support/Kalam/models/`).
- `HistoryManager` — persists transcription history.
- `NotificationService` — sounds + UNUserNotification feedback. Every failure path must surface here — no silent failures.

### Views (Sources/Kalam/Views/)
- `MainView` (popover, file picker, and popover drop target), `MainWindowView` (standalone file-transcription window), `SettingsView` (engine/model/language/hotkey), `WaveformView`, `HistoryView`, `RecordingIndicatorWindow` (floating overlay while recording).

### Key Flows
1. **Hotkey**: Cmd+Shift+Space (tap-toggle or hold-to-talk) → `AppState.handleHotkeyDown/Up` → record → stop → `performTranscription` (Sarvam or WhisperKit) → personal-dictionary corrections (`applyDictionary`) → paste at cursor + clipboard + history.
2. **UI recording**: MainView button → same flow without paste.
3. **File transcription**: drop an audio file onto the status icon or popover, or choose it with the file picker → `AppState.transcribeFile` → selected Sarvam or local Whisper engine → personal-dictionary corrections → clipboard + history.

## Dual Build System
- **Direct distribution** (`./build-app.sh`): full features (hotkey, paste-at-cursor).
- **App Store** (`./build-appstore.sh`): `-DAPP_STORE_BUILD`, no hotkey/CGEvent paste.

## Required Permissions (direct build)
- **Microphone** — recording.
- **Accessibility** — paste-at-cursor only. If the app is re-signed/rebuilt with a *different* identity, the System Settings checkbox stays on but the grant is dead: remove the entry and re-add the app.
- Notifications — feedback banners.

## Reliability invariants (learned the hard way — keep them)
- Never assume the input sample rate; always read it from the tap format.
- Never append audio samples via `Task { @MainActor }` from the tap.
- Every error path must produce a user-visible notification.
- Settings must persist (UserDefaults) — no in-memory-only defaults.
- Sarvam failures must fall back to local Whisper when a model is installed.
- Recordings must be bounded: auto-stop on sustained silence (2 min) and a hard cap (10 min), constants in AudioCaptureService. Auto-ended recordings go to clipboard + history, never paste-at-cursor.
- The menu bar icon mirrors state (red = recording, ink = transcribing); don't add separate flash/animation mechanisms that fight it.
- `install.sh` is also the updater: validate the downloaded app and its signature before touching the installed bundle, preserve the prior bundle recoverably, restore it after any failed or interrupted update, and never modify Application Support or preferences during an update.
