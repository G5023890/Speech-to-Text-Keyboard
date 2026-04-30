import Foundation

enum DictationProfile: String, CaseIterable, Identifiable {
    case mixedRuEn
    case hebrew

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mixedRuEn:
            return "RU+EN"
        case .hebrew:
            return "Hebrew"
        }
    }

    var whisperLanguageArgument: String? {
        switch self {
        case .mixedRuEn:
            return "auto"
        case .hebrew:
            return "he"
        }
    }

    var hotkeyDescription: String {
        switch self {
        case .mixedRuEn:
            return "Fn + Shift"
        case .hebrew:
            return "Fn + Shift + Control"
        }
    }
}
