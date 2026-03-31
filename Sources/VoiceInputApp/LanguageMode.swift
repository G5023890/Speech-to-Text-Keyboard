import Foundation

enum LanguageMode: String, CaseIterable {
    case auto
    case russianEnglish
    case russian
    case english
    case hebrew

    var title: String {
        switch self {
        case .auto:
            return "Auto"
        case .russianEnglish:
            return "Русский / English"
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
        case .auto, .russianEnglish:
            return nil
        case .russian:
            return "ru"
        case .english:
            return "en"
        case .hebrew:
            return "he"
        }
    }

    var whisperInitialPrompt: String? {
        switch self {
        case .auto:
            return "The speaker may switch between Russian, English, and Hebrew. Transcribe only what is spoken. Do not translate."
        case .russianEnglish:
            return "The speaker may switch freely between Russian and English, including within the same sentence. Preserve the original language of each word and phrase. Output Russian in Cyrillic and English in Latin. Do not translate."
        case .russian:
            return "The speaker speaks only Russian. Transcribe only Russian. Do not translate."
        case .english:
            return "The speaker speaks only English. Transcribe only English. Do not translate."
        case .hebrew:
            return "הדובר מדבר רק בעברית. יש לתמלל רק עברית. בלי תרגום ובלי שפות אחרות. פלט רק טקסט בעברית."
        }
    }
}
