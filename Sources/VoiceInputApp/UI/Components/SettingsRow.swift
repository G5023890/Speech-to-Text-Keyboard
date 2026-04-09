import SwiftUI

struct SettingsRow<Content: View>: View {

    let title: String
    let content: Content

    init(_ title: String,
         @ViewBuilder content: () -> Content) {

        self.title = title
        self.content = content()
    }

    var body: some View {

        HStack {

            Text(title)

            Spacer()

            content

        }
        .frame(height: VIConstants.settingsRowHeight)
        .padding(.horizontal, VISpacing.m)

    }
}
