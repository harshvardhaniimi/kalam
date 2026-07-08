# Kalam 🖋️

A native macOS menu bar app for speech-to-text dictation — built for Hindi + English (including code-mixed Hinglish), and private by default.
Local transcription runs on-device via OpenAI Whisper; an optional Sarvam AI cloud engine delivers the best Hindi accuracy available.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

🔒 **Private by Default** - The local Whisper engine keeps everything on your Mac: no cloud, no telemetry, no subscriptions.

🇮🇳 **Hindi + English, Properly** - Choose the Sarvam AI engine (Saaras v3) for the best Hindi/Hinglish accuracy — roughly half the word-error rate of Whisper large-v3 on spontaneous Hindi — with a code-mix mode that keeps Hinglish natural.
Saaras v3 supports 22 Indian languages (Hindi, Tamil, Telugu, Bengali, Marathi, Gujarati, Kannada, Malayalam, Punjabi, Odia, and more) plus Indian English, with automatic language detection.
Needs a free API key from [dashboard.sarvam.ai](https://dashboard.sarvam.ai); falls back to local Whisper automatically if the network fails.

📖 **Personal Dictionary** - Teach it the words engines keep getting wrong (names, acronyms, course codes).
Corrections are whole-word, case-insensitive, and apply to every transcript.

🎨 **Beautiful Native UI** - Retro-inspired design with modern refinement, featuring a menu bar app and full window interface.

🎙️ **Real-time Recording** - Record directly from your microphone with live audio level visualization.

📁 **File Transcription** - Drag & drop audio files (MP3, WAV, M4A, etc.) for batch transcription.

🌍 **Multi-language Support** - Transcribe in 50+ languages including English, Spanish, French, German, Chinese, Japanese, and more.

📊 **Multiple Model Sizes** - Choose from 5 model sizes (tiny to large) based on your needs and hardware capabilities.

💾 **History & Search** - Automatic history saving with full-text search across all transcriptions.

📤 **Export Options** - Export as Text, Markdown, JSON, or SRT subtitle format.

⚡ **Apple Silicon Optimized** - Leverages Metal and Accelerate frameworks for blazing-fast performance on M1/M2/M3 Macs.

⌨️ **Global Hotkey, Two Ways** - Tap Cmd+Shift+Space to start/stop, or hold it down and release — walkie-talkie style.
Text is automatically inserted at your cursor and copied to clipboard.

⏱️ **Live Recording Indicator** - A floating pill follows your cursor showing elapsed time and your real voice level; the menu bar icon turns red while recording and purple while transcribing.

🛑 **Forgiving by Design** - Recordings auto-stop after 2 minutes of silence or 10 minutes total, so a forgotten hotkey never becomes an hour-long recording.

🚀 **Auto-Setup** - First launch automatically downloads the base model, and Kalam can start itself at login (Settings → General).

🔔 **Smart Notifications** - Audio/visual feedback when recording starts, stops, transcription completes — and clear, actionable messages when something goes wrong.

## Screenshots

*(Menu Bar App)*
```
┌─────────────────────────────────────┐
│ 🖋️ Kalam                🕐 ⚙️       │
├─────────────────────────────────────┤
│                                     │
│   Ready to transcribe               │
│   Click record to start             │
│                                     │
│   [Waveform Visualization]          │
│                                     │
│        ● Record                     │
│                                     │
│   Model: Base • Language: Auto      │
└─────────────────────────────────────┘
```

## Installation

### Option 1: Quick Install (Recommended)

Run this in Terminal:
```bash
curl -sL https://raw.githubusercontent.com/harshvardhaniimi/kalam/main/install.sh | bash
```

Then right-click the app in Applications and select "Open" (first time only).

### Option 2: Build from Source

1. **Clone the repository:**
   ```bash
   git clone https://github.com/harshvardhaniimi/kalam.git
   cd whisper-mac
   ```

2. **Build the app:**
   ```bash
   ./build-app.sh
   ```

3. **Run:**
   ```bash
   open Kalam.app
   ```

Or open `Package.swift` in Xcode and press ⌘+R.

### Option 3: Manual Download

1. **Download** the latest `Kalam.zip` from [Releases](https://github.com/harshvardhaniimi/kalam/releases)
2. **Unzip** and move `Kalam.app` to your Applications folder
3. **Remove quarantine** (required for apps not notarized with Apple):
   ```bash
   xattr -cr /Applications/Kalam.app
   ```
4. **Open the app** - Right-click → Open (first time only)

## Rebranding

If you want to ship this as your own branded product:

1. Edit `release.config.sh` (app name, bundle ID, repo links, permission copy)
2. Run `./scripts/create-release.sh <version>` to generate release artifacts
3. (Optional) Run `./scripts/notarize-release.sh <version>` for Developer ID notarization
4. See `archive/LAUNCH_BLUEPRINT.md` for additional Gumroad/App Store planning notes

## Quick Start

### First Launch

1. **Launch the app** - A waveform icon will appear in your menu bar
2. **Wait for auto-download** - The base model (142 MB) downloads automatically on first launch
3. **Grant permissions** - Allow Microphone and Accessibility access when prompted
4. **You're ready!** - Press Cmd+Shift+Space from anywhere to start recording

### Using the Global Hotkey (Recommended)

The fastest way to transcribe — two styles, same key:

- **Tap to toggle**: press Cmd+Shift+Space, speak, press it again to stop and transcribe.
- **Hold to talk**: hold Cmd+Shift+Space down, speak, release — great for quick one-liners.

Either way, the text appears at your cursor and is copied to the clipboard.
A floating indicator near your cursor shows the elapsed time and your live voice level while recording.

**Example:** Writing an email? Click in the email body, press Cmd+Shift+Space, speak your message, press Cmd+Shift+Space again. The transcribed text appears in your email!

### Using the Menu Bar App

1. **Click the menu bar icon**
2. **Click "Record"** and speak
3. **Click "Stop Recording"** when done
4. **Copy to clipboard** to use the text elsewhere

### Transcribing Files

1. **Drag & drop** an audio file into the main window
2. **Wait** for processing (varies by file length and model size)
3. **Copy or export** the transcription

## Engine & Model Selection Guide

**Two engines** (Settings → Transcription Engine):

| Engine | Where it runs | Best for | Needs |
|--------|---------------|----------|-------|
| Local Whisper | On your Mac | Privacy, offline use, English | A downloaded model |
| Sarvam AI (Saaras v3) | Cloud API | Hindi, Hinglish, code-mixed speech | Free API key from [dashboard.sarvam.ai](https://dashboard.sarvam.ai) |

**Local Whisper models** (Settings → Speech Models):

| Model       | Size   | Speed  | Best For                                        |
|-------------|--------|--------|--------------------------------------------------|
| Tiny        | 75 MB  | ⚡⚡⚡⚡  | Quick English notes                              |
| Base        | 142 MB | ⚡⚡⚡   | General English use                              |
| Small       | 466 MB | ⚡⚡    | Better English accuracy                          |
| Medium      | 1.5 GB | ⚡     | High accuracy                                    |
| Large Turbo | 1.6 GB | ⚡⚡    | **Hindi + English — the only usable local option for Hindi** |
| Large       | 3.1 GB | ⚡     | Maximum accuracy, slowest                        |

**Recommendation:** use Sarvam for Hindi/Hinglish dictation and Large Turbo as your local model.
The tiny/base/small models are effectively English-only — their Hindi word-error rates are far too high for real use.

## System Requirements

- **macOS 14.0 (Sonoma) or later**
- **RAM:**
  - 8 GB minimum (for tiny/base models)
  - 16 GB recommended (for small/medium models)
  - 32 GB for large model
- **Storage:** 100 MB - 3 GB per model
- **Microphone** (for recording)

**Performance Notes:**
- Apple Silicon (M1/M2/M3) provides ~10x better performance than Intel
- Base model on M1: ~6 seconds to transcribe 1 minute of audio
- Real-time transcription possible on Apple Silicon with small models

## Privacy

🔒 **Private by default, honest about the exception:**

- ✅ With the **local Whisper engine** (default), all processing happens on your Mac — audio never leaves your device, no internet needed after the model download.
- ⚠️ With the optional **Sarvam AI engine**, recorded audio is sent to Sarvam's servers for transcription — that's the trade for the best Hindi accuracy. Switch engines any time in Settings.
- ✅ No data collection or telemetry in the app itself.
- ✅ Transcription history is stored locally only.
- ✅ Your Sarvam API key is stored in the macOS Keychain, never in plaintext.

Models are downloaded once from Hugging Face and stored locally:
```
~/Library/Application Support/Kalam/models/
```

## Technical Details

**Architecture:**
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Audio**: AVFoundation
- **ML Backend**: OpenAI Whisper via [WhisperKit](https://github.com/argmaxinc/WhisperKit) (CoreML)
- **Acceleration**: Apple Neural Engine + CoreML on Apple Silicon

**Design Philosophy:**
- Native macOS design patterns
- Retro-inspired but modern aesthetic
- Clean, minimal interface
- Keyboard-first workflow
- Subtle, purposeful animations

## Keyboard Shortcuts

- **Cmd+Shift+Space** (anywhere in macOS) - Tap to start/stop recording, or hold to talk; text auto-inserts at cursor
- `⌘+C` - Copy transcription

### Global Hotkey

The global hotkey (Cmd+Shift+Space) works out of the box - **no Accessibility permissions required** for the hotkey itself!

You can:
- Record from any application
- Have text automatically inserted at your cursor
- Text is also copied to clipboard as backup

**Note:** Text insertion at cursor still requires Accessibility permissions.

## Roadmap

- [x] Core transcription functionality
- [x] Menu bar app interface
- [x] Full window interface
- [x] Model management with auto-download
- [x] History with search
- [x] Export functionality
- [x] Global hotkey (Cmd+Shift+Space) for quick recording
- [x] Hold-to-talk (press and hold the hotkey, release to transcribe)
- [x] Text insertion at cursor position
- [x] Audio/visual feedback notifications
- [x] Sarvam AI engine for Hindi/Hinglish (with automatic local fallback)
- [x] Whisper large-v3-turbo model for local multilingual use
- [x] Personal dictionary (custom vocabulary corrections)
- [x] Auto-stop on silence / maximum duration
- [x] Launch at login
- [x] Live recording indicator with elapsed time
- [ ] Streaming transcription (real-time results via Sarvam WebSocket)
- [ ] Speaker diarization
- [ ] Timestamp display
- [ ] Configurable hotkey (currently Cmd+Shift+Space - no permissions required)
- [ ] App Store distribution

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues.

## Troubleshooting

**App doesn't appear in menu bar:**
- Check that `LSUIElement` is set in Info.plist
- Restart the app

**Global hotkey (Cmd+Shift+Space) not working:**
- Make sure the hotkey is enabled in Settings
- Check if another app is using the same hotkey (e.g., Spotlight, another app)
- Restart the app

**Text not inserting at cursor:**
- Enable Accessibility permissions (see above)
- The text is always copied to clipboard as a backup - use Cmd+V to paste
- Make sure you're focused in a text input field

**Microphone not working (checkbox looks enabled but recording fails):**
- macOS ties permissions to the app's code signature; after updating Kalam the old grant can go stale even though the checkbox stays on.
- Fix: `tccutil reset Microphone io.kalam.app` in Terminal, relaunch Kalam, and allow when prompted.
- Same idea for paste-at-cursor: remove the Kalam entry in System Settings → Privacy & Security → Accessibility and re-add `/Applications/Kalam.app`.

**Sarvam engine errors:**
- Check the API key in Settings (get one at dashboard.sarvam.ai) and your internet connection.
- Kalam automatically falls back to the local Whisper model when Sarvam is unreachable, so download a local model as a safety net.

**Model didn't auto-download on first launch:**
- Check internet connection
- Go to Settings and manually download the base model
- Check ~/Library/Application Support/Kalam/models/

**Poor transcription quality:**
- Try a larger model (small or medium)
- Ensure good audio quality (clear voice, minimal background noise)
- Check microphone input levels
- Speak clearly and avoid background noise

**Slow performance:**
- Use a smaller model (tiny or base)
- Close resource-intensive apps
- Check Activity Monitor for CPU/RAM usage

**Model download fails:**
- Check internet connection
- Try again (downloads can be large)
- Manually download from Hugging Face if needed

## Uninstall

To completely remove Kalam and all its data:

```bash
curl -sL https://raw.githubusercontent.com/harshvardhaniimi/kalam/main/uninstall.sh | bash
```

Or manually:
1. Quit Kalam
2. Delete `/Applications/Kalam.app`
3. Delete `~/Library/Application Support/Kalam/` (contains models and history)

## Contributing & Feedback

**We welcome your feedback!** This project is actively maintained and we'd love to hear from you:

- 🐛 **Bug Reports**: [Open an issue](https://github.com/harshvardhaniimi/kalam/issues) with detailed steps to reproduce
- 💡 **Feature Requests**: Describe the feature and why it would be useful
- 🔧 **Pull Requests**: Contributions are welcome! Please open an issue first to discuss major changes
- 💬 **General Feedback**: Share your experience using Kalam

### A Note on Development

This application was **entirely vibe coded** using [Claude Code](https://claude.ai/code) - Anthropic's AI coding assistant. The entire codebase, from architecture to implementation, was developed through conversational AI pair programming. We believe this represents an exciting new paradigm in software development.

If you encounter any quirks or have suggestions for improvement, please don't hesitate to reach out!

## Credits

- **OpenAI Whisper** - The incredible speech recognition model: https://github.com/openai/whisper
- **WhisperKit** - Swift-native Whisper on Apple platforms: https://github.com/argmaxinc/WhisperKit
- **Design inspiration** - Apple HIG, Claude.ai, classic Mac apps

## License

MIT License - see LICENSE file for details.

This project uses OpenAI's Whisper model, which is also licensed under MIT.

## Support

- 🐛 Report issues on GitHub
- ⭐ Star the project if you find it useful!

## Author

Created with [Claude Code](https://claude.ai/code) by **Dr. Harshvardhan**

- 🌐 Website: [harsh17.in](https://harsh17.in)
- 💻 GitHub: [@harshvardhaniimi](https://github.com/harshvardhaniimi)
- 🔗 LinkedIn: [harshvardhaniimi](https://www.linkedin.com/in/harshvardhaniimi/)
- 🧵 Threads: [@harsh17.in](https://www.threads.net/@harsh17.in)
- 📧 Email: hello@harsh17.in

---

**Note**: This app is not affiliated with OpenAI or Anthropic. Whisper is an open-source model created by OpenAI.
