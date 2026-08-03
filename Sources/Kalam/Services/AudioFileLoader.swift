import AVFoundation
import UniformTypeIdentifiers

struct LoadedAudioFile: Sendable {
    let samples: [Float]
    let duration: TimeInterval
}

enum AudioFileLoader {
    private static let transcriptionSampleRate: Double = 16_000
    private static let supportedExtensions: [String] = [
        "3g2", "3gp", "3gp2", "3gpp",
        "aac", "ac3", "adts", "aif", "aifc", "aiff", "amr", "au", "awb",
        "caf", "caff", "eac3", "ec3", "flac",
        "latm", "loas", "m1a", "m2a", "m4a", "m4b", "m4r", "m4v",
        "mov", "mp1", "mp2", "mp3", "mp4", "mpa", "mpeg", "mpg4",
        "oga", "ogg", "opus", "qt", "qta", "sd2", "snd", "w64", "wav", "wave", "xhe",
    ]
    private static let supportedExtensionSet = Set(supportedExtensions)

    /// Native audio plus movie containers whose audio track Kalam can extract.
    static let importContentTypes: [UTType] = [.audio, .movie] + supportedExtensions.compactMap {
        UTType(filenameExtension: $0)
    }

    static func isAudioFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }

        let pathExtension = url.pathExtension.lowercased()
        if supportedExtensionSet.contains(pathExtension) {
            return true
        }

        if let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = values.contentType,
           (contentType.conforms(to: .audio) || contentType.conforms(to: .movie)) {
            return true
        }

        guard let contentType = UTType(filenameExtension: pathExtension) else { return false }
        return contentType.conforms(to: .audio) || contentType.conforms(to: .movie)
    }

    /// Decode an audio file, downmix it to mono, and resample it to Kalam's
    /// 16 kHz transcription rate. Movie containers contribute only their
    /// audio track; video frames are never loaded or uploaded.
    static func load(url: URL) async throws -> LoadedAudioFile {
        guard isAudioFile(url) else {
            throw AudioFileError.unsupportedFormat
        }

        do {
            return try loadAudioFile(url: url)
        } catch {
            return try await loadMediaAsset(url: url)
        }
    }

    private static func loadAudioFile(url: URL) throws -> LoadedAudioFile {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        guard file.length > 0, sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0 else {
            throw AudioFileError.emptyFile
        }
        guard file.length <= Int64(UInt32.max) else {
            throw AudioFileError.fileTooLarge
        }

        let duration = Double(file.length) / sourceFormat.sampleRate
        let inputCapacity = AVAudioFrameCount(file.length)
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: inputCapacity
        ) else {
            throw AudioFileError.couldNotDecode
        }
        try file.read(into: inputBuffer)
        guard inputBuffer.frameLength > 0 else {
            throw AudioFileError.emptyFile
        }

        let targetRate = transcriptionSampleRate
        if sourceFormat.sampleRate == targetRate,
           sourceFormat.channelCount == 1,
           sourceFormat.commonFormat == .pcmFormatFloat32,
           let channel = inputBuffer.floatChannelData {
            let samples = Array(
                UnsafeBufferPointer(start: channel[0], count: Int(inputBuffer.frameLength))
            )
            return LoadedAudioFile(samples: samples, duration: duration)
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioFileError.couldNotConvert
        }

        let estimatedFrames = ceil(
            Double(inputBuffer.frameLength) * targetRate / sourceFormat.sampleRate
        ) + 1_024
        guard estimatedFrames <= Double(UInt32.max),
              let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount(estimatedFrames)
              ) else {
            throw AudioFileError.fileTooLarge
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .endOfStream
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error,
              conversionError == nil,
              outputBuffer.frameLength > 0,
              let channel = outputBuffer.floatChannelData else {
            throw AudioFileError.couldNotConvert
        }

        let samples = Array(
            UnsafeBufferPointer(start: channel[0], count: Int(outputBuffer.frameLength))
        )
        return LoadedAudioFile(samples: samples, duration: duration)
    }

    /// AVAudioFile handles dedicated audio formats efficiently. AVAssetReader
    /// is the fallback for MP4, MOV, M4V, QT, and other media containers that
    /// carry a decodable audio track.
    private static func loadMediaAsset(url: URL) async throws -> LoadedAudioFile {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = tracks.first else {
            throw AudioFileError.noAudioTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: transcriptionSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw AudioFileError.couldNotDecode
        }
        reader.add(output)
        guard reader.startReading() else {
            throw AudioFileError.assetReader(reader.error?.localizedDescription)
        }

        var samples: [Float] = []
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let byteCount = CMBlockBufferGetDataLength(blockBuffer)
            guard byteCount > 0, byteCount.isMultiple(of: MemoryLayout<Float>.size) else { continue }

            var bytes = [UInt8](repeating: 0, count: byteCount)
            let status = CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: byteCount,
                destination: &bytes
            )
            guard status == kCMBlockBufferNoErr else {
                throw AudioFileError.couldNotDecode
            }
            bytes.withUnsafeBytes { rawBuffer in
                samples.append(contentsOf: rawBuffer.bindMemory(to: Float.self))
            }
        }

        guard reader.status == .completed else {
            throw AudioFileError.assetReader(reader.error?.localizedDescription)
        }
        guard !samples.isEmpty else {
            throw AudioFileError.emptyFile
        }

        let assetDuration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(assetDuration)
        let duration = seconds.isFinite && seconds > 0
            ? seconds
            : Double(samples.count) / transcriptionSampleRate
        return LoadedAudioFile(samples: samples, duration: duration)
    }
}

enum AudioFileError: LocalizedError {
    case unsupportedFormat
    case emptyFile
    case couldNotDecode
    case couldNotConvert
    case fileTooLarge
    case noAudioTrack
    case assetReader(String?)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "That format is not supported. Try WAV, MP3, M4A, AAC, AIFF, CAF, FLAC, MP4, or MOV."
        case .emptyFile:
            return "The audio file is empty or unreadable."
        case .couldNotDecode:
            return "Kalam could not decode that audio file."
        case .couldNotConvert:
            return "Kalam could not prepare that audio file for transcription."
        case .fileTooLarge:
            return "That audio file is too large to process."
        case .noAudioTrack:
            return "That media file does not contain an audio track."
        case .assetReader(let detail):
            if let detail, !detail.isEmpty {
                return "Kalam could not read that media file: \(detail)"
            }
            return "Kalam could not read that media file."
        }
    }
}
