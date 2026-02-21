import Foundation
import SwiftUI

struct ModelOption: Identifiable, Hashable {
    let id: String
    let title: String
    let isRecommended: Bool
}

struct SettingsStats: Equatable {
    var todaySeconds: Double
    var weekSeconds: Double
    var monthSeconds: Double
    var totalSeconds: Double
    var sessions: Int
    var characters: Int
    var hasWeeklyAggregate: Bool
    var hasMonthlyAggregate: Bool
    var hasTotalAggregate: Bool

    static let mock = SettingsStats(
        todaySeconds: 118,
        weekSeconds: 724,
        monthSeconds: 2592,
        totalSeconds: 8040,
        sessions: 18,
        characters: 1438,
        hasWeeklyAggregate: true,
        hasMonthlyAggregate: true,
        hasTotalAggregate: true
    )
}

struct SettingsSnapshot: Equatable {
    var launchAtLoginEnabled: Bool
    var selectedHotkey: String
    var selectedModelID: String
    var installedModelCount: Int
    var totalModelCount: Int
    var updatesAvailable: Bool
    var lastCheckStatus: String
    var stats: SettingsStats
    var isCheckingUpdates: Bool
    var isUpdatingModels: Bool

    static let mock = SettingsSnapshot(
        launchAtLoginEnabled: true,
        selectedHotkey: HotkeyMode.shiftOption.rawValue,
        selectedModelID: TranscribeModel.mediumQ5.rawValue,
        installedModelCount: 3,
        totalModelCount: 3,
        updatesAvailable: false,
        lastCheckStatus: "Обновлений нет",
        stats: .mock,
        isCheckingUpdates: false,
        isUpdatingModels: false
    )
}

struct SettingsActions {
    var snapshot: () -> SettingsSnapshot
    var setLaunchAtLogin: (Bool) -> Void
    var setHotkey: (String) -> Void
    var setModel: (String) -> Void
    var checkUpdates: (@escaping (SettingsSnapshot) -> Void) -> Void
    var updateModels: (@escaping (SettingsSnapshot) -> Void) -> Void
    var resetStats: () -> Void

    static let mock = SettingsActions(
        snapshot: { .mock },
        setLaunchAtLogin: { _ in },
        setHotkey: { _ in },
        setModel: { _ in },
        checkUpdates: { completion in completion(.mock) },
        updateModels: { completion in completion(.mock) },
        resetStats: {}
    )
}

final class SettingsViewModel: ObservableObject {
    @Published private(set) var snapshot: SettingsSnapshot

    let hotkeyOptions: [HotkeyMode]
    let modelOptions: [ModelOption]

    private let actions: SettingsActions

    init(
        actions: SettingsActions = .mock,
        modelOptions: [ModelOption] = SettingsViewModel.defaultModelOptions,
        hotkeyOptions: [HotkeyMode] = HotkeyMode.allCases
    ) {
        self.actions = actions
        self.modelOptions = modelOptions
        self.hotkeyOptions = hotkeyOptions
        self.snapshot = actions.snapshot()
    }

    static let defaultModelOptions: [ModelOption] = [
        ModelOption(id: TranscribeModel.smallQ5.rawValue, title: "Быстрая", isRecommended: false),
        ModelOption(id: TranscribeModel.mediumQ5.rawValue, title: "Сбалансированная", isRecommended: true),
        ModelOption(id: TranscribeModel.largeV3TurboQ5.rawValue, title: "Максимальное качество", isRecommended: false)
    ]

    func isModelRecommended(_ modelID: String) -> Bool {
        modelOptions.first(where: { $0.id == modelID })?.isRecommended == true
    }

    func reload() {
        snapshot = actions.snapshot()
    }

    func applyLaunchAtLogin(_ enabled: Bool) {
        actions.setLaunchAtLogin(enabled)
        reload()
    }

    func applyHotkey(_ rawValue: String) {
        actions.setHotkey(rawValue)
        reload()
    }

    func applyModel(_ rawValue: String) {
        actions.setModel(rawValue)
        reload()
    }

    func checkUpdates() {
        guard !snapshot.isCheckingUpdates, !snapshot.isUpdatingModels else {
            return
        }
        actions.checkUpdates { [weak self] updated in
            DispatchQueue.main.async {
                self?.snapshot = updated
            }
        }
    }

    func updateModels() {
        guard !snapshot.isCheckingUpdates, !snapshot.isUpdatingModels else {
            return
        }
        let actions = self.actions
        Task { @MainActor [weak self] in
            guard let self else { return }
            let updated = await withCheckedContinuation { continuation in
                actions.updateModels { snapshot in
                    continuation.resume(returning: snapshot)
                }
            }
            self.snapshot = updated
        }
    }

    func resetStats() {
        actions.resetStats()
        reload()
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    @AppStorage("voice_input_launch_at_login") private var launchAtLogin = false
    @AppStorage("voice_input_hotkey_mode") private var hotkey = HotkeyMode.shiftOption.rawValue
    @AppStorage("voice_input_transcribe_model") private var selectedModelID = TranscribeModel.mediumQ5.rawValue

    private let pickerWidth: CGFloat = 260
    private let controlsColumnWidth: CGFloat = 360

    var body: some View {
        Form {
            Section("Общие") {
                Toggle("Запуск при входе", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        launchAtLogin = newValue
                        viewModel.applyLaunchAtLogin(newValue)
                    }
                ))

                settingsRow(label: "Горячая клавиша") {
                    Picker("", selection: Binding(
                        get: { hotkey },
                        set: { newValue in
                            hotkey = newValue
                            viewModel.applyHotkey(newValue)
                        }
                    )) {
                        ForEach(viewModel.hotkeyOptions, id: \.rawValue) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.large)
                    .frame(width: pickerWidth)
                }

                VStack(alignment: .leading, spacing: 8) {
                    settingsRow(label: "Модель") {
                        HStack(spacing: 8) {
                            Picker("", selection: Binding(
                                get: { selectedModelID },
                                set: { newValue in
                                    selectedModelID = newValue
                                    viewModel.applyModel(newValue)
                                }
                            )) {
                                ForEach(viewModel.modelOptions) { option in
                                    Text(option.title).tag(option.id)
                                }
                            }
                            .labelsHidden()
                            .controlSize(.large)
                            .frame(width: pickerWidth)

                            if viewModel.isModelRecommended(selectedModelID) {
                                Text("Рекомендуется")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }

                    Text("Установлено: \(viewModel.snapshot.installedModelCount) модели • Обновлений \(viewModel.snapshot.updatesAvailable ? "есть" : "нет")")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Модели") {
                HStack(alignment: .center, spacing: 12) {
                    Text(viewModel.snapshot.lastCheckStatus)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer(minLength: 12)

                    HStack(spacing: 8) {
                        Button("Проверить обновления") {
                            viewModel.checkUpdates()
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.snapshot.isCheckingUpdates || viewModel.snapshot.isUpdatingModels)

                        Button("Обновить") {
                            viewModel.updateModels()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.snapshot.updatesAvailable || viewModel.snapshot.isCheckingUpdates || viewModel.snapshot.isUpdatingModels)
                    }
                }
            }

            Section("Статистика") {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    statsGridRow("Сегодня", formattedDuration(viewModel.snapshot.stats.todaySeconds))
                    statsGridRow("Неделя", viewModel.snapshot.stats.hasWeeklyAggregate ? formattedDuration(viewModel.snapshot.stats.weekSeconds) : "—")
                    statsGridRow("Месяц", viewModel.snapshot.stats.hasMonthlyAggregate ? formattedDuration(viewModel.snapshot.stats.monthSeconds) : "—")
                    statsGridRow("Всего", viewModel.snapshot.stats.hasTotalAggregate ? formattedDuration(viewModel.snapshot.stats.totalSeconds) : "—")
                }

                Text("\(viewModel.snapshot.stats.sessions) диктовок • \(viewModel.snapshot.stats.characters) символов")
                    .foregroundStyle(.secondary)

                Button("Сбросить статистику", role: .destructive) {
                    viewModel.resetStats()
                }
                .buttonStyle(.bordered)
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(minWidth: 680, minHeight: 580)
        .onAppear {
            viewModel.reload()
            syncStorageFromSnapshot()
        }
        .onReceive(viewModel.$snapshot) { _ in
            syncStorageFromSnapshot()
        }
    }

    private func settingsRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label)
            Spacer(minLength: 12)
            content()
                .frame(width: controlsColumnWidth, alignment: .trailing)
        }
    }

    private func statsGridRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
            Text(value).monospacedDigit()
        }
    }

    private func syncStorageFromSnapshot() {
        launchAtLogin = viewModel.snapshot.launchAtLoginEnabled
        hotkey = viewModel.snapshot.selectedHotkey
        selectedModelID = viewModel.snapshot.selectedModelID
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
