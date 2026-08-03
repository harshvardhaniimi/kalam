import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDraggingFile = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            Divider()

            // Main content area
            ZStack {
                if appState.isProcessing {
                    processingView
                } else if !appState.currentTranscription.isEmpty {
                    transcriptionView
                } else {
                    emptyStateView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
            .onDrop(of: [.audio, .fileURL], isTargeted: $isDraggingFile) { providers in
                handleDrop(providers: providers)
            }
            .overlay(
                isDraggingFile ? dropOverlay : nil
            )

            Divider()

            // Waveform
            if appState.isRecording {
                WaveformView(audioLevel: appState.audioLevel)
                    .frame(height: 80)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .background(Color(NSColor.controlBackgroundColor))

                Divider()
            }

            // Bottom controls
            bottomControls
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text(AppBrand.displayName)
                .font(DesignSystem.Typography.title2)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Spacer()

            // Model selector
            Picker("Model", selection: $appState.selectedModel) {
                ForEach(WhisperModel.allCases) { model in
                    Text(model.displayName).tag(model)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            // Language selector
            Picker("Language", selection: $appState.selectedLanguage) {
                Text("Auto").tag("auto")
                Divider()
                Text("English").tag("en")
                Text("Spanish").tag("es")
                Text("French").tag("fr")
                Text("German").tag("de")
                Text("Italian").tag("it")
                Text("Portuguese").tag("pt")
                Text("Chinese").tag("zh")
                Text("Japanese").tag("ja")
                Text("Korean").tag("ko")
                Text("Russian").tag("ru")
                Text("Arabic").tag("ar")
                Text("Hindi").tag("hi")
                Divider()
                Text("Dutch").tag("nl")
                Text("Turkish").tag("tr")
                Text("Polish").tag("pl")
                Text("Swedish").tag("sv")
                Text("Thai").tag("th")
                Text("Vietnamese").tag("vi")
                Text("Ukrainian").tag("uk")
                Text("Czech").tag("cs")
                Text("Greek").tag("el")
                Text("Tamil").tag("ta")
                Text("Urdu").tag("ur")
                Text("Bengali").tag("bn")
            }
            .pickerStyle(.menu)
            .frame(width: 120)
        }
        .padding(DesignSystem.Spacing.md)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Content Views

    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 96))
                .foregroundColor(DesignSystem.Colors.accent.opacity(0.3))

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Ready to Transcribe")
                    .font(DesignSystem.Typography.largeTitle)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text("Record audio or drag & drop an audio file to get started")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            HStack(spacing: DesignSystem.Spacing.md) {
                VStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "mic.fill")
                        .font(.title)
                        .foregroundColor(DesignSystem.Colors.accent)
                    Text("Record")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                Text("or")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                VStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.title)
                        .foregroundColor(DesignSystem.Colors.accent)
                    Text("Drop File")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .padding(.top, DesignSystem.Spacing.lg)
        }
    }

    private var processingView: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            ProgressView()
                .scaleEffect(2)

            Text("Transcribing Audio...")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            Text("This may take a moment depending on the audio length")
                .font(DesignSystem.Typography.callout)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }

    private var transcriptionView: some View {
        ScrollView {
            Text(appState.currentTranscription)
                .font(DesignSystem.Typography.transcription)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .padding(DesignSystem.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
            .stroke(DesignSystem.Colors.accent, lineWidth: 3)
            .background(
                DesignSystem.Colors.accent.opacity(0.1)
                    .cornerRadius(DesignSystem.CornerRadius.lg)
            )
            .padding(DesignSystem.Spacing.lg)
            .overlay(
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(DesignSystem.Colors.accent)
                    Text("Drop audio file to transcribe")
                        .font(DesignSystem.Typography.title3)
                        .foregroundColor(DesignSystem.Colors.accent)
                }
            )
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            // Record/Stop button
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
                        Circle()
                            .fill(DesignSystem.Colors.recordingRed)
                            .frame(width: 12, height: 12)
                        Text("Stop Recording")
                    } else {
                        Image(systemName: "mic.circle.fill")
                        Text("Record")
                    }
                }
                .frame(minWidth: 140)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(appState.isProcessing)

            // Copy button
            if !appState.currentTranscription.isEmpty {
                Button(action: {
                    appState.copyToClipboard()
                }) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: "doc.on.clipboard")
                        Text("Copy")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            Spacer()

            // Status
            if appState.isRecording {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Circle()
                        .fill(DesignSystem.Colors.recordingRed)
                        .frame(width: 8, height: 8)

                    Text(formatDuration(appState.recordingDuration))
                        .font(DesignSystem.Typography.body.monospacedDigit())
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Helpers

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }

            Task {
                await appState.transcribeFile(url: url)
            }
        }

        return true
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
