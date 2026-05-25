import Foundation

struct WhisperLanguage: Identifiable, Hashable {
    let code: String
    let displayName: String

    var id: String { code }

    static let auto = WhisperLanguage(code: "auto", displayName: "Auto")

    static let practicalSmallLanguages: [WhisperLanguage] = [
        .auto,
        WhisperLanguage(code: "ru", displayName: "Russian"),
        WhisperLanguage(code: "en", displayName: "English"),
        WhisperLanguage(code: "he", displayName: "Hebrew"),
        WhisperLanguage(code: "uk", displayName: "Ukrainian"),
        WhisperLanguage(code: "fr", displayName: "French"),
        WhisperLanguage(code: "es", displayName: "Spanish"),
        WhisperLanguage(code: "de", displayName: "German"),
        WhisperLanguage(code: "it", displayName: "Italian"),
        WhisperLanguage(code: "pl", displayName: "Polish"),
        WhisperLanguage(code: "pt", displayName: "Portuguese"),
        WhisperLanguage(code: "nl", displayName: "Dutch"),
        WhisperLanguage(code: "tr", displayName: "Turkish"),
        WhisperLanguage(code: "ar", displayName: "Arabic"),
        WhisperLanguage(code: "zh", displayName: "Chinese"),
        WhisperLanguage(code: "ja", displayName: "Japanese"),
        WhisperLanguage(code: "ko", displayName: "Korean")
    ]

    static func language(for code: String) -> WhisperLanguage {
        practicalSmallLanguages.first { $0.code == code } ?? .auto
    }
}

@MainActor
final class LanguageSettings: ObservableObject {
    @Published var secondaryLanguageCode: String {
        didSet {
            UserDefaults.standard.set(secondaryLanguageCode, forKey: Self.secondaryLanguageKey)
        }
    }

    var primaryLanguage: WhisperLanguage { .auto }
    var secondaryLanguage: WhisperLanguage { WhisperLanguage.language(for: secondaryLanguageCode) }

    init(userDefaults: UserDefaults = .standard) {
        let saved = userDefaults.string(forKey: Self.secondaryLanguageKey) ?? "he"
        secondaryLanguageCode = WhisperLanguage.language(for: saved).code
    }

    func language(for profile: DictationProfile) -> WhisperLanguage {
        switch profile {
        case .mixedRuEn:
            return primaryLanguage
        case .hebrew:
            return secondaryLanguage
        }
    }

    private static let secondaryLanguageKey = "secondaryHotkeyLanguageCode"
}
