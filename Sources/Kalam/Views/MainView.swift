import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var justCopied = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Main content
            if appState.isProcessing {
                processingView
            } else if !appState.currentTranscription.isEmpty {
                transcriptionView
            } else {
                emptyStateView
            }

            Divider()

            // Waveform
            if appState.isRecording {
                WaveformView(audioLevel: appState.audioLevel)
                    .frame(height: 60)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)

                Divider()
            }

            // Controls
            controls
        }
        .frame(width: 400, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var isErrorTranscription: Bool {
        appState.currentTranscription.hasPrefix("Error:")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "waveform")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.accent)

            // Bilingual wordmark — the app's whole point in two scripts
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                Text(AppBrand.displayName)
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Text("कलम")
                    .font(.system(size: 15))
                    .foregroundColor(DesignSystem.Colors.accent)
            }

            Spacer()

            Button(action: { showHistory.toggle() }) {
                Image(systemName: "clock")
            }
            .buttonStyle(IconButtonStyle())
            .help("History")
            .popover(isPresented: $showHistory) {
                HistoryView()
                    .environmentObject(appState)
                    .frame(width: 500, height: 600)
            }

            Button(action: { showSettings.toggle() }) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(IconButtonStyle())
            .help("Settings")
            .popover(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(appState)
                    .frame(width: 500, height: 400)
            }

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Image(systemName: "power")
            }
            .buttonStyle(IconButtonStyle())
            .help("Quit \(AppBrand.displayName)")
        }
        .padding(DesignSystem.Spacing.md)
    }

    // MARK: - Content Views

    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.accent.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: "mic")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.ink)
            }

            Text("Ready to transcribe")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            #if APP_STORE_BUILD
            Text("Click Record, speak in Hindi, English, or both")
                .font(DesignSystem.Typography.subheadline)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            #else
            VStack(spacing: DesignSystem.Spacing.sm) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    KeyCap("⌘")
                    KeyCap("⇧")
                    KeyCap("Space")
                }
                Text("tap to toggle or hold to talk — Hindi, English, or both")
                    .font(DesignSystem.Typography.footnote)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var processingView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)

            VStack(spacing: DesignSystem.Spacing.xs) {
                Text("Transcribing…")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Text("with \(engineName)")
                    .font(DesignSystem.Typography.footnote)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcriptionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                if isErrorTranscription {
                    Label {
                        Text(appState.currentTranscription)
                            .font(DesignSystem.Typography.subheadline)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundColor(DesignSystem.Colors.error)
                } else {
                    Text(appState.currentTranscription)
                        .font(DesignSystem.Typography.transcription)
                        .lineSpacing(6)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .textSelection(.enabled)
                }
            }
            .padding(DesignSystem.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .fill(isErrorTranscription
                          ? DesignSystem.Colors.error.opacity(0.06)
                          : DesignSystem.Colors.accent.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .strokeBorder(isErrorTranscription
                                          ? DesignSystem.Colors.error.opacity(0.15)
                                          : DesignSystem.Colors.accent.opacity(0.15),
                                          lineWidth: 1)
                    )
            )
            .padding(DesignSystem.Spacing.md)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Record button
            Button(action: {
                Task {
                    if appState.isRecording {
                        await appState.stopRecording()
                    } else {
                        try? await appState.startRecording()
                    }
                }
            }) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    if appState.isRecording {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 16))
                        Text("Stop & Transcribe")
                    } else {
                        Image(systemName: "record.circle")
                            .font(.system(size: 20))
                        Text("Record")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(tint: appState.isRecording
                                            ? DesignSystem.Colors.recordingRed
                                            : DesignSystem.Colors.ink))
            .disabled(appState.isProcessing)

            // Copy button (only show when there's a real transcription)
            if !appState.currentTranscription.isEmpty && !isErrorTranscription {
                Button(action: {
                    appState.copyToClipboard()
                    justCopied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        justCopied = false
                    }
                }) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: justCopied ? "checkmark" : "doc.on.clipboard")
                        Text(justCopied ? "Copied" : "Copy transcript")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            // Status bar
            statusBar
        }
        .padding(DesignSystem.Spacing.md)
    }

    private var engineName: String {
        switch appState.transcriptionEngine {
        case .sarvam:
            return "Sarvam Saaras"
        case .local:
            return "Whisper \(appState.selectedModel.displayName)"
        }
    }

    private var engineDetail: String {
        switch appState.transcriptionEngine {
        case .sarvam:
            return "Sarvam Saaras · \(appState.sarvamMode == .codemix ? "Hinglish" : "native script")"
        case .local:
            let language = appState.selectedLanguage == "auto"
                ? "auto"
                : appState.selectedLanguage.uppercased()
            return "Whisper \(appState.selectedModel.displayName) · \(language)"
        }
    }

    private var statusBar: some View {
        HStack {
            Text(engineDetail)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            Spacer()

            if appState.isRecording {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Circle()
                        .fill(DesignSystem.Colors.recordingRed)
                        .frame(width: 7, height: 7)
                    Text(formatDuration(appState.recordingDuration))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.recordingRed)
                        .monospacedDigit()
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// A small keyboard-key chip, e.g. ⌘ ⇧ Space.
private struct KeyCap: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundColor(DesignSystem.Colors.textPrimary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            )
    }
}
