import SwiftUI

struct SettingsShortcutRow: View {

    let title: String
    let shortcut: String

    var body: some View {

        SettingsRow(title) {

            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))

        }
    }
}