import Foundation

enum DictationProfile: String, CaseIterable, Identifiable {
    case mixedRuEn
    case hebrew

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mixedRuEn:
            return "Primary"
        case .hebrew:
            return "Secondary"
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
