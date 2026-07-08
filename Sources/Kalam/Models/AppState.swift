import SwiftUI
import Combine
import UserNotifications
import ServiceManagement

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    // Recording state
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var isProcessing = false
    @Published var isDownloadingModel = false

    // Audio
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0.0

    // Transcription
    @Published var currentTranscription: String = ""
    @Published var transcriptionHistory: [Transcription] = []

    // Settings (persisted so they survive app restarts)
    @Published var selectedModel: WhisperModel {
        didSet { UserDefaults.standard.set(selectedModel.rawValue, forKey: "settings.model") }
    }
    @Published var selectedLanguage: String {
        didSet { UserDefaults.standard.set(selectedLanguage, forKey: "settings.language") }
    }
    @Published var selectedAudioDevice: String?
    @Published var globalHotkeyEnabled: Bool {
        didSet { UserDefaults.standard.set(globalHotkeyEnabled, forKey: "settings.hotkeyEnabled") }
    }
    @Published var transcriptionEngine: TranscriptionEngine {
        didSet { UserDefaults.standard.set(transcriptionEngine.rawValue, forKey: "settings.engine") }
    }
    @Published var sarvamAPIKey: String {
        didSet {
            // Keychain, not UserDefaults — a paid API credential doesn't
            // belong in a plaintext preferences plist.
            if sarvamAPIKey.isEmpty {
                KeychainHelper.deleteAPIKey()
            } else {
                KeychainHelper.saveAPIKey(sarvamAPIKey)
            }
        }
    }
    @Published var sarvamMode: SarvamMode {
        didSet { UserDefaults.standard.set(sarvamMode.rawValue, forKey: "settings.sarvamMode") }
    }
    @Published var dictionaryRules: [DictionaryRule] {
        didSet {
            if let data = try? JSONEncoder().encode(dictionaryRules) {
                UserDefaults.standard.set(data, forKey: "settings.dictionary")
            }
        }
    }

    // Services
    let audioService: AudioCaptureService
    let whisperService: WhisperService
    let modelManager: ModelManager
    let historyManager: HistoryManager
    let hotkeyManager: GlobalHotkeyManager
    let notificationService: NotificationService
    let sarvamService = SarvamService()
    let textInsertionService = TextInsertionService.shared

    private var cancellables = Set<AnyCancellable>()
    private var isInitialSetupComplete = false

    init() {
        let defaults = UserDefaults.standard
        self.selectedModel = WhisperModel(rawValue: defaults.string(forKey: "settings.model") ?? "") ?? .base
        self.selectedLanguage = defaults.string(forKey: "settings.language") ?? "auto"
        self.globalHotkeyEnabled = defaults.object(forKey: "settings.hotkeyEnabled") as? Bool ?? true
        self.transcriptionEngine = TranscriptionEngine(rawValue: defaults.string(forKey: "settings.engine") ?? "") ?? .local
        // Keychain first; then any legacy plaintext value (migrated below);
        // then the shell env var (terminal launches only — Finder-launched
        // apps don't see shell exports).
        let legacyKey = defaults.string(forKey: "settings.sarvamKey")
        self.sarvamAPIKey = KeychainHelper.loadAPIKey()
            ?? legacyKey
            ?? ProcessInfo.processInfo.environment["SARVAM_API_KEY"] ?? ""
        self.sarvamMode = SarvamMode(rawValue: defaults.string(forKey: "settings.sarvamMode") ?? "") ?? .codemix
        if let dictionaryData = defaults.data(forKey: "settings.dictionary"),
           let rules = try? JSONDecoder().decode([DictionaryRule].self, from: dictionaryData) {
            self.dictionaryRules = rules
        } else {
            self.dictionaryRules = []
        }

        // One-time migration: move a legacy plaintext key into the keychain
        if let legacyKey, !legacyKey.isEmpty {
            KeychainHelper.saveAPIKey(legacyKey)
            defaults.removeObject(forKey: "settings.sarvamKey")
        }

        self.audioService = AudioCaptureService()
        self.whisperService = WhisperService()
        self.modelManager = ModelManager()
        self.historyManager = HistoryManager()
        self.hotkeyManager = GlobalHotkeyManager()
        self.notificationService = NotificationService.shared

        setupBindings()
        #if !APP_STORE_BUILD
        setupHotkeyHandler()
        #endif
    }

    /// True when at least one engine is ready to produce a transcript.
    var canTranscribe: Bool {
        (transcriptionEngine == .sarvam && !sarvamAPIKey.trimmingCharacters(in: .whitespaces).isEmpty)
            || modelManager.isModelInstalled(selectedModel)
    }

    /// Route transcription through the selected engine. If Sarvam fails
    /// (offline, bad key, API error) and a local model is available, fall
    /// back to it so a network blip never eats a recording.
    private func performTranscription(audioSamples: [Float]) async throws -> String {
        if transcriptionEngine == .sarvam {
            do {
                let text = try await sarvamService.transcribe(
                    audioSamples: audioSamples,
                    apiKey: sarvamAPIKey,
                    mode: sarvamMode
                )
                return applyDictionary(text)
            } catch {
                guard modelManager.isModelInstalled(selectedModel) else { throw error }
                notificationService.showError("\(error.localizedDescription) Falling back to local Whisper.")
            }
        }

        guard modelManager.isModelInstalled(selectedModel) else {
            throw TranscriptionError.modelNotFound
        }
        let text = try await whisperService.transcribe(
            audioSamples: audioSamples,
            model: selectedModel,
            modelPath: modelManager.getModelPath(selectedModel),
            language: selectedLanguage == "auto" ? nil : selectedLanguage
        )
        return applyDictionary(text)
    }

    private func setupBindings() {
        // Bind audio level
        audioService.$audioLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &$audioLevel)

        // Bind recording duration
        audioService.$duration
            .receive(on: DispatchQueue.main)
            .assign(to: &$recordingDuration)

        // If the input device changes mid-recording (AirPods connect, mic
        // unplugged), the engine stops delivering audio. End the recording
        // gracefully with whatever was captured instead of failing silently.
        audioService.onRecordingInterrupted = { [weak self] in
            Task { @MainActor in
                await self?.endRecordingAutomatically(because: "Audio device changed — recording stopped.")
            }
        }

        // Forgotten recordings end themselves: sustained silence or the
        // hard duration cap.
        audioService.onAutoStop = { [weak self] reason in
            Task { @MainActor in
                let message: String
                switch reason {
                case .silence:
                    message = "Recording stopped after \(Int(AudioCaptureService.silenceTimeout / 60)) minutes of silence."
                case .maxDuration:
                    message = "Recording stopped at the \(Int(AudioCaptureService.maxRecordingDuration / 60))-minute limit."
                }
                await self?.endRecordingAutomatically(because: message)
            }
        }
    }

    /// End a recording the user didn't stop themselves (device change,
    /// silence timeout, duration cap): transcribe what was captured and put
    /// it on the clipboard — pasting at the cursor minutes later would land
    /// somewhere unintended.
    private func endRecordingAutomatically(because message: String) async {
        guard isRecording else { return }
        notificationService.showError(message)
        await stopRecording()
        if !currentTranscription.isEmpty && !currentTranscription.hasPrefix("Error:") {
            copyToClipboard()
            notificationService.showTranscriptionComplete(text: currentTranscription)
        }
    }

    // MARK: - Launch at login

    /// Whether the app is registered as a login item. Kept in sync with
    /// SMAppService; toggled from Settings via setLaunchAtLogin.
    @Published var launchAtLogin: Bool = false

    func refreshLaunchAtLogin() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            notificationService.showError("Could not update the login item: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    #if !APP_STORE_BUILD
    /// A press held longer than this is hold-to-talk: release stops and
    /// transcribes. A quicker press is a tap: recording continues until the
    /// next tap.
    static let holdToTalkThreshold: TimeInterval = 0.6

    private var hotkeyPressStartedRecording = false
    private var hotkeyPressDownTime: Date?

    private func setupHotkeyHandler() {
        hotkeyManager.onHotkeyDown = { [weak self] in
            Task { @MainActor in
                await self?.handleHotkeyDown()
            }
        }
        hotkeyManager.onHotkeyUp = { [weak self] in
            Task { @MainActor in
                await self?.handleHotkeyUp()
            }
        }
    }
    #endif

    func initialize() async {
        guard !isInitialSetupComplete else { return }

        refreshLaunchAtLogin()

        #if !APP_STORE_BUILD
        // Register the hotkey FIRST — model download/pre-load below can take
        // 20s to minutes, and the hotkey must not be dead in that window.
        if globalHotkeyEnabled {
            hotkeyManager.startMonitoring()
        }
        #endif

        // Auto-download default model if not installed
        if !modelManager.isModelInstalled(selectedModel) {
            isDownloadingModel = true
            do {
                try await modelManager.downloadModel(selectedModel)
            } catch {
                print("Failed to download default model: \(error)")
                notificationService.showError("Could not download the \(selectedModel.displayName) model — check your internet connection, then retry from Settings.")
            }
            isDownloadingModel = false
        }

        // Pre-load the selected model into WhisperKit
        if modelManager.isModelInstalled(selectedModel) {
            let modelPath = modelManager.getModelPath(selectedModel)
            do {
                try await whisperService.loadModel(selectedModel, modelPath: modelPath)
            } catch {
                print("Failed to pre-load model: \(error)")
                notificationService.showError("Failed to load the \(selectedModel.displayName) model. Try re-downloading it from Settings.")
            }
        }

        // Show ready notification (only if we have a bundle)
        if Bundle.main.bundleIdentifier != nil {
            let content = UNMutableNotificationContent()
            content.title = "\(AppBrand.displayName) Ready!"
            #if APP_STORE_BUILD
            content.body = "Click the menu bar icon to start recording"
            #else
            content.body = "Press Cmd+Shift+Space to start recording"
            #endif
            content.sound = .default
            let request = UNNotificationRequest(identifier: "ready", content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        } else {
            print("\(AppBrand.displayName) Ready!")
        }

        isInitialSetupComplete = true
    }

    #if !APP_STORE_BUILD
    private func handleHotkeyDown() async {
        if isRecording {
            // Ignore key-repeat of the press that started this recording
            guard !hotkeyPressStartedRecording else { return }
            await stopRecordingAndTranscribe()
        } else if !isProcessing && !isDownloadingModel {
            hotkeyPressStartedRecording = true
            hotkeyPressDownTime = Date()
            await startRecordingWithFeedback()
        } else {
            // Busy transcribing — acknowledge the press so it doesn't feel dead
            NSSound.beep()
        }
    }

    private func handleHotkeyUp() async {
        defer { hotkeyPressStartedRecording = false }
        guard hotkeyPressStartedRecording,
              isRecording,
              let downTime = hotkeyPressDownTime,
              Date().timeIntervalSince(downTime) >= Self.holdToTalkThreshold
        else { return }
        // Held to talk: release ends the recording
        await stopRecordingAndTranscribe()
    }
    #endif

    /// Apply personal-dictionary corrections (case-insensitive, whole-word,
    /// longest rule first so multi-word entries win over their substrings).
    func applyDictionary(_ text: String) -> String {
        guard !dictionaryRules.isEmpty else { return text }
        var result = text
        for rule in dictionaryRules.sorted(by: { $0.from.count > $1.from.count }) {
            let from = rule.from.trimmingCharacters(in: .whitespaces)
            guard !from.isEmpty else { continue }
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: from) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: rule.to)
            )
        }
        return result
    }

    func startRecording() async throws {
        guard canTranscribe else {
            throw TranscriptionError.modelNotFound
        }
        currentTranscription = ""
        try await audioService.startRecording()
        isRecording = true
    }

    func startRecordingWithFeedback() async {
        do {
            guard canTranscribe else {
                notificationService.showError("No transcription engine ready — download a model in Settings, or add your Sarvam API key.")
                return
            }
            currentTranscription = ""
            try await audioService.startRecording()
            isRecording = true

            // Show visual indicator at cursor
            RecordingIndicatorWindow.shared.show()

            // Show feedback
            notificationService.showRecordingStarted()
        } catch {
            print("Failed to start recording: \(error)")
            notificationService.showError("Failed to start recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() async {
        // Hide recording indicator
        RecordingIndicatorWindow.shared.hide()

        guard let audioSamples = await audioService.stopRecordingAndGetSamples() else {
            isRecording = false
            notificationService.showError("No audio was captured — check your microphone input.")
            return
        }

        isRecording = false
        isProcessing = true

        do {
            let result = try await performTranscription(audioSamples: audioSamples)

            currentTranscription = result

            // Save to history
            let transcription = Transcription(
                text: result,
                date: Date(),
                duration: recordingDuration,
                language: selectedLanguage
            )
            historyManager.save(transcription)
            transcriptionHistory.insert(transcription, at: 0)

        } catch {
            print("Transcription error: \(error)")
            currentTranscription = "Error: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    func stopRecordingAndTranscribe() async {
        // Hide recording indicator
        RecordingIndicatorWindow.shared.hide()

        guard let audioSamples = await audioService.stopRecordingAndGetSamples() else {
            isRecording = false
            notificationService.showError("No audio was captured — check your microphone input.")
            return
        }

        isRecording = false
        notificationService.showRecordingStopped()
        isProcessing = true

        do {
            let result = try await performTranscription(audioSamples: audioSamples)

            currentTranscription = result

            // Save to history
            let transcription = Transcription(
                text: result,
                date: Date(),
                duration: recordingDuration,
                language: selectedLanguage
            )
            historyManager.save(transcription)
            transcriptionHistory.insert(transcription, at: 0)

            // Insert at cursor (direct distribution) or just copy to clipboard (App Store)
            #if APP_STORE_BUILD
            copyToClipboard()
            #else
            textInsertionService.insertTextAtCursor(result)
            #endif
            notificationService.showTranscriptionComplete(text: result)

        } catch {
            print("Transcription error: \(error)")
            let errorMessage = "Error: \(error.localizedDescription)"
            currentTranscription = errorMessage
            notificationService.showError(errorMessage)
        }

        isProcessing = false
    }

    func transcribeFile(url: URL) async throws {
        guard modelManager.isModelInstalled(selectedModel) else {
            throw TranscriptionError.modelNotFound
        }

        isProcessing = true
        defer { isProcessing = false }

        let modelPath = modelManager.getModelPath(selectedModel)
        let result = applyDictionary(try await whisperService.transcribeFile(
            url: url,
            model: selectedModel,
            modelPath: modelPath,
            language: selectedLanguage == "auto" ? nil : selectedLanguage
        ))

        currentTranscription = result

        let transcription = Transcription(
            text: result,
            date: Date(),
            duration: 0,
            language: selectedLanguage,
            sourceFile: url.lastPathComponent
        )
        historyManager.save(transcription)
        transcriptionHistory.insert(transcription, at: 0)
    }

    func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(currentTranscription, forType: .string)
    }

    func toggleGlobalHotkey() {
        #if !APP_STORE_BUILD
        if globalHotkeyEnabled {
            hotkeyManager.startMonitoring()
        } else {
            hotkeyManager.stopMonitoring()
        }
        #endif
    }
}
