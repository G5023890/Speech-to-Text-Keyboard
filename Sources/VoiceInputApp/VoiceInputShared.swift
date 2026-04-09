import Foundation

enum VoiceInputShared {
    static let appBundleIdentifier = "com.grigorym.voiceinput"
    static let controlExtensionBundleIdentifier = "com.grigorym.voiceinput.controls"
    static let executableName = "VoiceInputApp"
    static let controlKind = "com.grigorym.voiceinput.status"
    static let openURLScheme = "voiceinput"
    static let openURLHost = "open"
    static let showsMenuBarIconDefaultsKey = "voice_input_show_menu_bar_icon"
    static let controlOpenURL = URL(string: "\(openURLScheme)://\(openURLHost)")!

    static func showsMenuBarIcon(userDefaults: UserDefaults = .standard) -> Bool {
        if userDefaults.object(forKey: showsMenuBarIconDefaultsKey) == nil {
            return true
        }
        return userDefaults.bool(forKey: showsMenuBarIconDefaultsKey)
    }
}
