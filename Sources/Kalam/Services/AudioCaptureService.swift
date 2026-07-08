import AVFoundation
import Combine

/// Collects samples from the audio render thread without actor hops.
/// The tap callback appends synchronously under a lock, so no audio is
/// lost or reordered, and stop() can drain everything deterministically.
private final class SampleAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    func reset() {
        lock.lock(); defer { lock.unlock() }
        samples.removeAll()
    }

    func append(_ newSamples: UnsafeBufferPointer<Float>) {
        lock.lock(); defer { lock.unlock() }
        samples.append(contentsOf: newSamples)
    }

    func drain() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let out = samples
        samples = []
        return out
    }
}

@MainActor
class AudioCaptureService: ObservableObject {
    @Published var audioLevel: Float = 0.0
    @Published var duration: TimeInterval = 0.0
    @Published var isRecording = false

    /// Called if the audio engine's configuration changes mid-recording
    /// (input device switched, AirPods connected/disconnected, etc.).
    var onRecordingInterrupted: (() -> Void)?

    /// Called when a recording ends itself — sustained silence or the
    /// maximum duration cap. Keeps forgotten recordings from running
    /// forever (unbounded memory, wasted Sarvam credits).
    var onAutoStop: ((AutoStopReason) -> Void)?

    enum AutoStopReason {
        case silence
        case maxDuration
    }

    /// Normalized level below which a buffer counts as silence.
    /// Speech typically sits well above 0.3 on this scale.
    static let silenceLevel: Float = 0.08
    /// Auto-stop after this much continuous silence.
    static let silenceTimeout: TimeInterval = 120
    /// Hard cap on a single recording.
    static let maxRecordingDuration: TimeInterval = 600

    private var lastVoiceDate: Date?
    private var autoStopFired = false

    private var audioEngine: AVAudioEngine?
    private var recordingStartTime: Date?
    private var levelTimer: Timer?
    private var configChangeObserver: NSObjectProtocol?

    private let accumulator = SampleAccumulator()
    /// Sample rate the current/last recording was captured at.
    private var captureSampleRate: Double = 0

    static let whisperSampleRate: Double = 16000

    func requestPermission() async throws -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func startRecording() async throws {
        let hasPermission = try await requestPermission()
        guard hasPermission else {
            throw AudioError.permissionDenied
        }

        // Tear down any previous engine before starting fresh
        teardownEngine()

        let engine = AVAudioEngine()
        audioEngine = engine
        let input = engine.inputNode

        let recordingFormat = input.outputFormat(forBus: 0)

        // A 0 Hz / 0-channel format means there is no usable input device
        // (or the microphone permission was just revoked). Installing a tap
        // with this format would crash, so fail loudly instead.
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            teardownEngine()
            throw AudioError.noInputDevice
        }

        // Record at whatever rate the device actually runs (built-in mic 48kHz,
        // many USB mics 44.1kHz, Bluetooth headsets 16-24kHz). We resample to
        // 16kHz at stop time using the real rate — never assume 48kHz.
        captureSampleRate = recordingFormat.sampleRate
        accumulator.reset()

        let accumulator = self.accumulator
        input.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else { return }

            // Append synchronously on the render thread — an async hop here
            // loses the tail of the recording and can reorder buffers.
            let frames = Int(buffer.frameLength)
            accumulator.append(UnsafeBufferPointer(start: channelData[0], count: frames))

            // Level metering is display-only, so it may hop to the main actor.
            var sum: Float = 0
            for i in 0..<frames {
                let s = channelData[0][i]
                sum += s * s
            }
            let rms = sqrt(sum / Float(frames))
            let avgPower = 20 * log10(max(rms, .leastNonzeroMagnitude))
            let normalizedPower = max(0, min(1, (avgPower + 50) / 50))
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.audioLevel = normalizedPower
                if normalizedPower > Self.silenceLevel {
                    self.lastVoiceDate = Date()
                }
            }
        }

        do {
            try engine.start()
        } catch {
            teardownEngine()
            throw AudioError.engineInitFailed
        }

        // If the input device changes mid-recording the engine stops delivering
        // audio silently. Surface it so the recording can end gracefully.
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.onRecordingInterrupted?()
            }
        }

        recordingStartTime = Date()
        lastVoiceDate = Date()
        autoStopFired = false
        isRecording = true

        let startTime = recordingStartTime
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let startTime = startTime else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.duration = Date().timeIntervalSince(startTime)
                self.checkAutoStop()
            }
        }
    }

    private func checkAutoStop() {
        guard !autoStopFired else { return }

        if duration >= Self.maxRecordingDuration {
            autoStopFired = true
            onAutoStop?(.maxDuration)
        } else if let lastVoice = lastVoiceDate,
                  Date().timeIntervalSince(lastVoice) >= Self.silenceTimeout {
            autoStopFired = true
            onAutoStop?(.silence)
        }
    }

    /// Stop recording and return 16kHz mono float samples for WhisperKit.
    /// Returns nil if no audio was captured.
    func stopRecordingAndGetSamples() async -> [Float]? {
        levelTimer?.invalidate()
        levelTimer = nil

        teardownEngine()

        isRecording = false
        audioLevel = 0.0

        let captured = accumulator.drain()
        guard !captured.isEmpty, captureSampleRate > 0 else { return nil }

        return resampleToWhisperRate(captured, from: captureSampleRate)
    }

    private func teardownEngine() {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
    }

    /// Convert captured mono samples from their native rate to 16kHz using
    /// AVAudioConverter (proper anti-aliasing). Falls back to linear
    /// interpolation if the converter cannot be created.
    private func resampleToWhisperRate(_ samples: [Float], from sourceRate: Double) -> [Float] {
        let targetRate = Self.whisperSampleRate
        guard sourceRate != targetRate else { return samples }

        guard
            let sourceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sourceRate, channels: 1, interleaved: false),
            let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetRate, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: sourceFormat, to: targetFormat),
            let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count))
        else {
            return linearResample(samples, from: sourceRate, to: targetRate)
        }

        inputBuffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            inputBuffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }

        let outputCapacity = AVAudioFrameCount(Double(samples.count) * targetRate / sourceRate) + 1
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            return linearResample(samples, from: sourceRate, to: targetRate)
        }

        var fed = false
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if fed {
                outStatus.pointee = .endOfStream
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard error == nil, outputBuffer.frameLength > 0, let out = outputBuffer.floatChannelData else {
            return linearResample(samples, from: sourceRate, to: targetRate)
        }

        return Array(UnsafeBufferPointer(start: out[0], count: Int(outputBuffer.frameLength)))
    }

    private func linearResample(_ samples: [Float], from: Double, to: Double) -> [Float] {
        guard from != to else { return samples }

        let ratio = from / to
        let outputLength = Int(Double(samples.count) / ratio)
        var output = [Float]()
        output.reserveCapacity(outputLength)

        for i in 0..<outputLength {
            let position = Double(i) * ratio
            let index = Int(position)
            let fraction = Float(position - Double(index))

            if index + 1 < samples.count {
                let sample = samples[index] * (1 - fraction) + samples[index + 1] * fraction
                output.append(sample)
            } else if index < samples.count {
                output.append(samples[index])
            }
        }

        return output
    }
}

enum AudioError: LocalizedError {
    case permissionDenied
    case engineInitFailed
    case noInputDevice

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied. Please enable in System Settings."
        case .engineInitFailed:
            return "Failed to initialize audio engine."
        case .noInputDevice:
            return "No audio input device found."
        }
    }
}
