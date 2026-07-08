import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var newRuleFrom = ""
    @State private var newRuleTo = ""

    private var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? version
        return "\(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(DesignSystem.Typography.title2)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()
            }
            .padding(DesignSystem.Spacing.md)

            Divider()

            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    // General section
                    generalSection

                    Divider()

                    #if !APP_STORE_BUILD
                    // Hotkey section
                    hotkeySection

                    Divider()
                    #endif

                    // Engine section
                    engineSection

                    Divider()

                    // Models section
                    modelSection

                    Divider()

                    // Language section
                    languageSection

                    Divider()

                    // Personal dictionary section
                    dictionarySection

                    Divider()

                    // About section
                    aboutSection
                }
                .padding(DesignSystem.Spacing.md)
            }
        }
        .frame(width: 500, height: 500)
    }

    // MARK: - General Section

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("General")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Toggle(isOn: Binding(
                get: { appState.launchAtLogin },
                set: { appState.setLaunchAtLogin($0) }
            )) {
                Text("Start \(AppBrand.displayName) at login")
                    .font(DesignSystem.Typography.body)
            }

            Text("Recording stops by itself after \(Int(AudioCaptureService.silenceTimeout / 60)) minutes of silence or \(Int(AudioCaptureService.maxRecordingDuration / 60)) minutes total — the transcript is kept and copied to the clipboard.")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }

    #if !APP_STORE_BUILD
    // MARK: - Hotkey Section

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Global Hotkey")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Toggle(isOn: $appState.globalHotkeyEnabled) {
                Text("Enable Cmd+Shift+Space hotkey")
                    .font(DesignSystem.Typography.body)
            }
            .onChange(of: appState.globalHotkeyEnabled) {
                appState.toggleGlobalHotkey()
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("How it works:")
                    .font(DesignSystem.Typography.callout)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .fontWeight(.semibold)

                Text("• Tap Cmd+Shift+Space to start, tap again to stop")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Text("• Or hold it down, speak, and release — walkie-talkie style")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Text("• Text is automatically inserted at your cursor and copied to clipboard")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .padding(DesignSystem.Spacing.sm)
            .background(DesignSystem.Colors.accent.opacity(0.1))
            .cornerRadius(DesignSystem.CornerRadius.sm)
        }
    }
    #endif

    // MARK: - Engine Section

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Transcription Engine")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Picker("Engine", selection: $appState.transcriptionEngine) {
                ForEach(TranscriptionEngine.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            if appState.transcriptionEngine == .sarvam {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    SecureField("Sarvam API key (dashboard.sarvam.ai)", text: $appState.sarvamAPIKey)
                        .textFieldStyle(.roundedBorder)

                    Picker("Output style", selection: $appState.sarvamMode) {
                        ForEach(SarvamMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("Sarvam Saaras v3 is markedly more accurate for Hindi and Hinglish than Whisper. Audio is sent to Sarvam's servers; if the request fails, \(AppBrand.displayName) falls back to your local Whisper model automatically.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .padding(DesignSystem.Spacing.sm)
                .background(DesignSystem.Colors.accent.opacity(0.1))
                .cornerRadius(DesignSystem.CornerRadius.sm)
            } else {
                Text("Local Whisper runs fully on-device. For Hindi + English, use the Large Turbo model — the smaller models are effectively English-only.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
    }

    // MARK: - Model Section

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Speech Models")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Text("Download and manage Whisper models. Larger models provide better accuracy but require more resources.")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            VStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(WhisperModel.allCases) { model in
                    ModelRow(model: model, modelManager: appState.modelManager, appState: appState)
                }
            }
        }
    }

    // MARK: - Language Section

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Default Language")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Picker("Language", selection: $appState.selectedLanguage) {
                Text("Auto Detect").tag("auto")
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
                Text("Indonesian").tag("id")
                Text("Thai").tag("th")
                Text("Vietnamese").tag("vi")
                Text("Hebrew").tag("he")
                Text("Ukrainian").tag("uk")
                Text("Malay").tag("ms")
                Text("Czech").tag("cs")
                Text("Romanian").tag("ro")
                Text("Danish").tag("da")
                Text("Finnish").tag("fi")
                Text("Hungarian").tag("hu")
                Text("Norwegian").tag("no")
                Text("Greek").tag("el")
                Text("Tamil").tag("ta")
                Text("Urdu").tag("ur")
                Text("Bengali").tag("bn")
                Text("Catalan").tag("ca")
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - Personal Dictionary Section

    private var dictionarySection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Personal Dictionary")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Text("Fix words the engines keep getting wrong — names, acronyms, course codes. Corrections apply to every transcript, whole-word and case-insensitive.")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            ForEach(appState.dictionaryRules) { rule in
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(rule.from)
                        .font(DesignSystem.Typography.callout)
                        .foregroundColor(DesignSystem.Colors.textSecondary)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.Colors.accent)

                    Text(rule.to)
                        .font(DesignSystem.Typography.callout)
                        .fontWeight(.medium)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Spacer()

                    Button(action: {
                        appState.dictionaryRules.removeAll { $0.id == rule.id }
                    }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("Remove correction")
                }
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(DesignSystem.CornerRadius.sm)
            }

            HStack(spacing: DesignSystem.Spacing.sm) {
                TextField("Heard as…", text: $newRuleFrom)
                    .textFieldStyle(.roundedBorder)

                Image(systemName: "arrow.right")
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.Colors.accent)

                TextField("Replace with…", text: $newRuleTo)
                    .textFieldStyle(.roundedBorder)

                Button("Add") {
                    addDictionaryRule()
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(newRuleFrom.trimmingCharacters(in: .whitespaces).isEmpty
                          || newRuleTo.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addDictionaryRule() {
        let from = newRuleFrom.trimmingCharacters(in: .whitespaces)
        let to = newRuleTo.trimmingCharacters(in: .whitespaces)
        guard !from.isEmpty, !to.isEmpty else { return }
        appState.dictionaryRules.append(DictionaryRule(from: from, to: to))
        newRuleFrom = ""
        newRuleTo = ""
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                Text("About")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text("कलम")
                    .font(.system(size: 14))
                    .foregroundColor(DesignSystem.Colors.accent.opacity(0.5))
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack {
                    Text("Version:")
                        .font(DesignSystem.Typography.callout)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Text(appVersionLabel)
                        .font(DesignSystem.Typography.callout)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }

                HStack {
                    Text("Powered by:")
                        .font(DesignSystem.Typography.callout)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Text("OpenAI Whisper (via WhisperKit)")
                        .font(DesignSystem.Typography.callout)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }

                HStack {
                    Text("App:")
                        .font(DesignSystem.Typography.callout)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Text(AppBrand.displayName)
                        .font(DesignSystem.Typography.callout)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }

                HStack {
                    Text("Bundle ID:")
                        .font(DesignSystem.Typography.callout)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Text(Bundle.main.bundleIdentifier ?? "Unknown")
                        .font(DesignSystem.Typography.callout)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
            }

            Text(appState.transcriptionEngine == .local
                 ? "All processing happens locally on your device. Your audio never leaves your computer."
                 : "Sarvam engine selected: recorded audio is sent to Sarvam AI for transcription.")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .padding(.top, DesignSystem.Spacing.xs)
        }
    }
}

struct ModelRow: View {
    let model: WhisperModel
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Model info
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(DesignSystem.Typography.callout)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text("\(model.description) • \(model.fileSize)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            // Status/Actions
            if modelManager.isModelInstalled(model) {
                // Select button
                if appState.selectedModel == model {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(DesignSystem.Colors.success)
                        Text("Selected")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.success)
                    }
                } else {
                    Button("Select") {
                        appState.selectedModel = model
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                // Delete button (disabled for currently selected model)
                Button(action: {
                    try? modelManager.deleteModel(model)
                }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(IconButtonStyle())
                .disabled(appState.selectedModel == model)
                .help(appState.selectedModel == model ? "Cannot delete selected model" : "Delete model")

            } else if let progress = modelManager.downloadProgress[model] {
                // Downloading
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ProgressView(value: progress)
                        .frame(width: 80)
                    Text("\(Int(progress * 100))%")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .monospacedDigit()
                }
            } else {
                // Download button
                Button("Download") {
                    Task {
                        try? await modelManager.downloadModel(model)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(modelManager.isDownloading)
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(DesignSystem.CornerRadius.sm)
    }
}
