import SwiftUI

struct SettingsSidebarItem: View {

    let icon: String
    let title: String
    let selected: Bool

    var body: some View {

        HStack(spacing: 10) {

            Image(systemName: icon)

            Text(title)

            Spacer()

        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            selected ? Color.accentColor.opacity(0.15) : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))

    }
}