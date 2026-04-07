# Kalam 🎤

A beautiful, native macOS app for speech-to-text transcription powered by OpenAI Whisper. Completely local, private, and free.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

✨ **Completely Local** - All processing happens on your Mac. No cloud, no subscriptions, no data leaves your computer.

🎨 **Beautiful Native UI** - Retro-inspired design with modern refinement, featuring a menu bar app and full window interface.

🎙️ **Real-time Recording** - Record directly from your microphone with live audio level visualization.

📁 **File Transcription** - Drag & drop audio files (MP3, WAV, M4A, etc.) for batch transcription.

🌍 **Multi-language Support** - Transcribe in 50+ languages including English, Spanish, French, German, Chinese, Japanese, and more.

📊 **Multiple Model Sizes** - Choose from 5 model sizes (tiny to large) based on your needs and hardware capabilities.

💾 **History & Search** - Automatic history saving with full-text search across all transcriptions.

📤 **Export Options** - Export as Text, Markdown, JSON, or SRT subtitle format.

⚡ **Apple Silicon Optimized** - Leverages Metal and Accelerate frameworks for blazing-fast performance on M1/M2/M3 Macs.

⌨️ **Global Hotkey** - Press Cmd+Shift+Space to start/stop recording from anywhere. Text is automatically inserted at your cursor and copied to clipboard.

🚀 **Auto-Setup** - First launch automatically downloads the base model. No manual setup required - just install and use!

🔔 **Smart Notifications** - Audio/visual feedback when recording starts, stops, and transcription completes.

## Screenshots

*(Menu Bar App)*
```
┌─────────────────────────────────────┐
│ 🎤 Kalam                🕐 ⚙️       │
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

The fastest way to transcribe:

1. **Start recording** - Press Cmd+Shift+Space (anywhere in macOS)
2. **Speak** - Say what you want to transcribe
3. **Stop & transcribe** - Press Cmd+Shift+Space again
4. **Done!** - Text appears at your cursor and is copied to clipboard

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

## Model Selection Guide

| Model  | Size   | Speed  | Accuracy | Best For                    |
|--------|--------|--------|----------|-----------------------------|
| Tiny   | 75 MB  | ⚡⚡⚡⚡  | ⭐⭐     | Quick notes, older hardware |
| Base   | 142 MB | ⚡⚡⚡   | ⭐⭐⭐    | General use (recommended)   |
| Small  | 466 MB | ⚡⚡    | ⭐⭐⭐⭐   | Better accuracy             |
| Medium | 1.5 GB | ⚡     | ⭐⭐⭐⭐⭐  | High accuracy, good hardware|
| Large  | 2.9 GB | ⚡     | ⭐⭐⭐⭐⭐⭐ | Best accuracy, powerful Macs|

**Recommendation:**
- **M1/M2/M3 Macs**: Start with Base or Small
- **Intel Macs**: Start with Tiny or Base
- **Quick notes**: Tiny or Base
- **Important transcriptions**: Small or Medium

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

🔒 **Your privacy is paramount:**

- ✅ All processing happens locally on your Mac
- ✅ No internet connection required (except for model downloads)
- ✅ No data collection or telemetry
- ✅ No cloud services or external APIs
- ✅ Audio never leaves your device
- ✅ Transcription history stored locally only
- ✅ You have full control over all data

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

- **Cmd+Shift+Space** (anywhere in macOS) - Start/stop recording with auto-insert at cursor
- `⌘+C` - Copy transcription
- `⌘+,` - Settings (coming soon)
- `⌘+H` - Show history (coming soon)

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
- [x] Text insertion at cursor position
- [x] Audio/visual feedback notifications
- [ ] Streaming transcription (real-time results)
- [ ] Custom vocabulary support
- [ ] Speaker diarization
- [ ] Timestamp display
- [ ] Additional keyboard shortcuts
- [ ] Dark/light mode customization
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

**Microphone not working:**
- System Settings → Privacy & Security → Microphone
- Enable permission for Kalam

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

- 🌐 Website: [harshvardhan.dev](https://harshvardhan.dev)
- 🐦 Twitter: [@harshvardhan_](https://twitter.com/harshvardhan_)
- 📧 Email: hello@harshvardhan.dev

---

**Note**: This app is not affiliated with OpenAI or Anthropic. Whisper is an open-source model created by OpenAI.
