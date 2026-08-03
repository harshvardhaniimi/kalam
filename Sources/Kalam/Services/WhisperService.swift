import Foundation
import WhisperKit

@MainActor
class WhisperService: ObservableObject {
    @Published var isModelLoaded = false

    private var whisperKit: WhisperKit?
    private var currentModelName: String?

    init() {}

    /// Load (or switch to) a specific model. Idempotent if already loaded.
    func loadModel(_ model: WhisperModel, modelPath: URL) async throws {
        let modelName = model.whisperKitModelName

        // Skip if this exact model is already loaded
        if currentModelName == modelName, whisperKit != nil, isModelLoaded {
            return
        }

        // Unload previous model if switching
        if whisperKit != nil {
            await whisperKit?.unloadModels()
            whisperKit = nil
            isModelLoaded = false
        }

        do {
            let config = WhisperKitConfig(
                modelFolder: modelPath.path,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )

            whisperKit = try await WhisperKit(config)
            currentModelName = modelName
            isModelLoaded = true
        } catch {
            isModelLoaded = false
            throw TranscriptionError.initializationFailed
        }
    }

    /// Transcribe from raw audio samples (from live recording).
    /// Expects 16kHz mono float samples.
    func transcribe(
        audioSamples: [Float],
        model: WhisperModel,
        modelPath: URL,
        language: String? = nil
    ) async throws -> String {
        try await loadModel(model, modelPath: modelPath)

        guard let whisperKit = whisperKit else {
            throw TranscriptionError.contextNotInitialized
        }

        var options = DecodingOptions()
        if let language = language, language != "auto" {
            options.language = language
            options.usePrefillPrompt = true
        } else {
            options.language = nil
            options.detectLanguage = true
        }

        let results = try await whisperKit.transcribe(
            audioArray: audioSamples,
            decodeOptions: options
        )

        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespaces)

        guard !text.isEmpty else {
            throw TranscriptionError.processingFailed
        }

        return text
    }

    /// Direct WhisperKit file transcription for dedicated audio formats.
    /// AppState normally uses AudioFileLoader so both engines share the wider
    /// Core Audio and MP4/QuickTime container support.
    func transcribeFile(
        url: URL,
        model: WhisperModel,
        modelPath: URL,
        language: String? = nil
    ) async throws -> String {
        try await loadModel(model, modelPath: modelPath)

        guard let whisperKit = whisperKit else {
            throw TranscriptionError.contextNotInitialized
        }

        var options = DecodingOptions()
        if let language = language, language != "auto" {
            options.language = language
            options.usePrefillPrompt = true
        } else {
            options.language = nil
            options.detectLanguage = true
        }

        let results = try await whisperKit.transcribe(
            audioPath: url.path,
            decodeOptions: options
        )

        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespaces)

        guard !text.isEmpty else {
            throw TranscriptionError.processingFailed
        }

        return text
    }

    /// Unload model to free memory
    func unloadModel() async {
        await whisperKit?.unloadModels()
        whisperKit = nil
        currentModelName = nil
        isModelLoaded = false
    }

    /// No-op — Whisper doesn't need SFSpeechRecognizer authorization
    func requestAuthorization() async -> Bool {
        return true
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotFound
    case initializationFailed
    case contextNotInitialized
    case processingFailed
    case invalidAudioFile
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Model not found. Please download it first."
        case .initializationFailed:
            return "Failed to initialize Whisper engine."
        case .contextNotInitialized:
            return "Whisper engine not initialized."
        case .processingFailed:
            return "Failed to process audio. No speech detected."
        case .invalidAudioFile:
            return "Invalid or unsupported audio file format."
        case .permissionDenied:
            return "Microphone permission denied. Please enable in System Settings."
        }
    }
}
