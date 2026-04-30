import SwiftUI

@main
struct LocalSTTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(appState: appDelegate.appState)
                .frame(width: 560, height: 520)
        }
    }
}
