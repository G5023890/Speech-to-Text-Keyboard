import SwiftUI

struct SettingsSection<Content: View>: View {

    let title: String
    let content: Content

    init(_ title: String,
         @ViewBuilder content: () -> Content) {

        self.title = title
        self.content = content()
    }

    var body: some View {

        VStack(alignment: .leading, spacing: VISpacing.s) {

            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                content
            }
            .background(.regularMaterial)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: VIConstants.cornerRadius
                )
            )

        }
    }
}
