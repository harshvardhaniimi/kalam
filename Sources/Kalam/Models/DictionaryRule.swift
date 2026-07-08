import Foundation

/// A personal-dictionary correction applied to every transcript:
/// whatever the engine heard (`from`) becomes what the user means (`to`).
/// Case-insensitive, whole-word.
struct DictionaryRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var from: String
    var to: String
}
