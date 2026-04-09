import SwiftUI

struct SettingsToggleRow: View {

    let title: String
    @Binding var value: Bool

    var body: some View {

        SettingsRow(title) {

            Toggle("", isOn: $value)
                .labelsHidden()

        }
    }
}