import Foundation

enum LanguageMode: String, CaseIterable {
    case auto
    case russian
    case english
    case hebrew

    var title: String {
        switch self {
        case .auto:
            return "Auto (RU/EN/HE)"
        case .russian:
            return "Русский"
        case .english:
            return "English"
        case .hebrew:
            return "עברית"
        }
    }

    var whisperLanguageCode: String? {
        switch self {
        case .auto:
            return nil
        case .russian:
            return "ru"
        case .english:
            return "en"
        case .hebrew:
            return "he"
        }
    }
}
