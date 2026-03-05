import SwiftUI

struct SettingsPickerRow<T: Hashable>: View {

    let title: String
    @Binding var selection: T
    let options: [T]
    var optionTitle: (T) -> String = { String(describing: $0) }

    var body: some View {

        SettingsRow(title) {

            Picker("", selection: $selection) {

                ForEach(options, id: \.self) { option in
                    Text(optionTitle(option))
                        .tag(option)
                }

            }
            .labelsHidden()
            .font(VITypography.rowValue)

        }
    }
}
