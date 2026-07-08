import Foundation

enum WhisperModel: String, CaseIterable, Identifiable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"
    case turbo = "turbo"
    case large = "large"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .turbo: return "Large Turbo"
        default:     return rawValue.capitalized
        }
    }

    /// WhisperKit CoreML model identifier for downloading from HuggingFace.
    /// Note: "openai_whisper-large-v3-v20240930" is OpenAI's large-v3-turbo
    /// (named by release date). The "_turbo"-suffixed variants in the repo
    /// are Argmax's own decoder experiments — don't use those for Hindi.
    var whisperKitModelName: String {
        switch self {
        case .tiny:   return "openai_whisper-tiny"
        case .base:   return "openai_whisper-base"
        case .small:  return "openai_whisper-small"
        case .medium: return "openai_whisper-medium"
        case .turbo:  return "openai_whisper-large-v3-v20240930"
        case .large:  return "openai_whisper-large-v3"
        }
    }

    /// Directory name where this model is stored locally.
    var folderName: String {
        whisperKitModelName
    }

    var fileSize: String {
        switch self {
        case .tiny:   return "~70 MB"
        case .base:   return "~140 MB"
        case .small:  return "~470 MB"
        case .medium: return "~1.5 GB"
        case .turbo:  return "~1.6 GB"
        case .large:  return "~3.1 GB"
        }
    }

    var description: String {
        switch self {
        case .tiny:   return "Fast, English only in practice"
        case .base:   return "Balanced for English; poor for Hindi"
        case .small:  return "Better accuracy; still weak for Hindi"
        case .medium: return "High accuracy"
        case .turbo:  return "Best multilingual (Hindi + English) - recommended"
        case .large:  return "Best accuracy (large-v3), slowest"
        }
    }
}
