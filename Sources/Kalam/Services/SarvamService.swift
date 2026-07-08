import Foundation

/// Which backend turns audio into text.
enum TranscriptionEngine: String, CaseIterable, Identifiable {
    /// On-device Whisper via WhisperKit. Private, works offline.
    case local
    /// Sarvam AI Saaras v3 cloud API — much stronger for Hindi/Hinglish
    /// (roughly half the WER of Whisper large-v3 on spontaneous Hindi).
    case sarvam

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local:  return "Local Whisper (offline, private)"
        case .sarvam: return "Sarvam AI (cloud, best for Hindi + English)"
        }
    }
}

/// Output style for Sarvam transcription.
enum SarvamMode: String, CaseIterable, Identifiable {
    /// Native script output (Hindi in Devanagari, English in Latin).
    case transcribe
    /// Natural code-mixed output — Hinglish stays Hinglish.
    case codemix

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .transcribe: return "Native script (Devanagari for Hindi)"
        case .codemix:    return "Code-mixed (natural Hinglish)"
        }
    }
}

/// Client for Sarvam AI's speech-to-text REST API (Saaras v3).
/// https://docs.sarvam.ai — POST https://api.sarvam.ai/speech-to-text
/// The REST endpoint accepts ~30s of audio per request, so longer
/// recordings are chunked and the transcripts joined.
@MainActor
class SarvamService {
    static let endpoint = URL(string: "https://api.sarvam.ai/speech-to-text")!
    static let model = "saaras:v3"
    /// Stay under the ~30s per-request cap with some margin.
    static let chunkSeconds = 25.0

    /// Transcribe 16kHz mono float samples via the Sarvam API.
    func transcribe(audioSamples: [Float], apiKey: String, mode: SarvamMode) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw SarvamError.missingAPIKey
        }

        let sampleRate = Int(AudioCaptureService.whisperSampleRate)
        let chunkSize = Int(Self.chunkSeconds * Double(sampleRate))

        var transcripts: [String] = []
        var start = 0
        while start < audioSamples.count {
            let end = min(start + chunkSize, audioSamples.count)
            let chunk = Array(audioSamples[start..<end])
            start = end

            let wav = Self.makeWAV(samples: chunk, sampleRate: sampleRate)
            let transcript = try await transcribeChunk(wav: wav, apiKey: key, mode: mode)
            if !transcript.isEmpty {
                transcripts.append(transcript)
            }
        }

        let text = transcripts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            throw SarvamError.emptyTranscript
        }
        return text
    }

    private func transcribeChunk(wav: Data, apiKey: String, mode: SarvamMode) async throws -> String {
        let boundary = "kalam-\(UUID().uuidString)"
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(apiKey, forHTTPHeaderField: "api-subscription-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func addField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        addField("model", Self.model)
        addField("language_code", "unknown")  // auto-detect Hindi/English per utterance
        addField("mode", mode.rawValue)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SarvamError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SarvamError.network("Invalid response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw SarvamError.api(status: http.statusCode, message: String(message))
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let transcript = json["transcript"] as? String
        else {
            throw SarvamError.network("Unexpected response format")
        }

        return transcript.trimmingCharacters(in: .whitespaces)
    }

    /// Build a 16-bit PCM mono WAV file from float samples.
    static func makeWAV(samples: [Float], sampleRate: Int) -> Data {
        var int16Samples = [Int16]()
        int16Samples.reserveCapacity(samples.count)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            int16Samples.append(Int16(clamped * Float(Int16.max)))
        }

        let dataSize = UInt32(int16Samples.count * 2)
        let rate = UInt32(sampleRate)
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: (36 + dataSize).littleEndian) { Data($0) })
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // PCM
        data.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: rate.littleEndian) { Data($0) })
        let byteRate = rate * UInt32(numChannels) * UInt32(bitsPerSample) / 8
        data.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        let blockAlign = numChannels * bitsPerSample / 8
        data.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        data.append("data".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        int16Samples.withUnsafeBufferPointer { buf in
            data.append(UnsafeBufferPointer(start: UnsafeRawPointer(buf.baseAddress!).assumingMemoryBound(to: UInt8.self), count: buf.count * 2))
        }

        return data
    }
}

enum SarvamError: LocalizedError {
    case missingAPIKey
    case network(String)
    case api(status: Int, message: String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Sarvam API key not set. Add it in Settings, or switch to Local Whisper."
        case .network(let detail):
            return "Could not reach Sarvam AI: \(detail)"
        case .api(let status, let message):
            return "Sarvam API error \(status): \(message)"
        case .emptyTranscript:
            return "Sarvam returned no speech."
        }
    }
}
