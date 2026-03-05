import SwiftUI

struct StatsCard: View {

    let title: String
    let value: String
    let subtitle: String

    var body: some View {

        VStack(alignment: .leading, spacing: 4) {

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2)
                .bold()

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)

        }
        .padding(VISpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(
            RoundedRectangle(
                cornerRadius: VIConstants.cornerRadius
            )
        )

    }
}