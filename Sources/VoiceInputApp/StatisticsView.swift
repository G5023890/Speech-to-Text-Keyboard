import SwiftUI

struct StatisticsView: View {
    let stats: SettingsStats
    let onReset: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VISpacing.xl) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: VISpacing.l
                ) {
                    StatsCard(
                        title: "Сегодня",
                        value: formattedDuration(stats.todaySeconds),
                        subtitle: "\(stats.todayWords.formatted()) слов"
                    )

                    StatsCard(
                        title: "Неделя",
                        value: stats.hasWeeklyAggregate ? formattedDuration(stats.weekSeconds) : "—",
                        subtitle: stats.hasWeeklyAggregate ? "\(stats.weekWords.formatted()) слов" : ""
                    )

                    StatsCard(
                        title: "Месяц",
                        value: stats.hasMonthlyAggregate ? formattedDuration(stats.monthSeconds) : "—",
                        subtitle: stats.hasMonthlyAggregate ? "\(stats.monthWords.formatted()) слов" : ""
                    )

                    StatsCard(
                        title: "Всего",
                        value: stats.hasTotalAggregate ? formattedDuration(stats.totalSeconds) : "—",
                        subtitle: "\(stats.words.formatted()) слов"
                    )
                }

                SettingsSection("Итоги") {
                    SettingsRow("Диктовок") {
                        Text("\(stats.sessions.formatted())")
                            .font(VITypography.rowValue)
                            .foregroundStyle(.secondary)
                    }

                    SettingsRow("Слов") {
                        Text("\(stats.words.formatted())")
                            .font(VITypography.rowValue)
                            .foregroundStyle(.secondary)
                    }

                    SettingsRow("Действия") {
                        Button("Сбросить статистику", role: .destructive) {
                            onReset()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(VISpacing.xl)
            .frame(width: VIConstants.settingsWidth, alignment: .leading)
        }
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            return "\(hours)ч \(String(format: "%02d", minutes))м"
        }
        if minutes > 0 {
            return "\(minutes)м \(String(format: "%02d", secs))с"
        }
        return "\(secs)с"
    }
}
