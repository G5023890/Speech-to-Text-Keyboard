import Foundation
import SwiftUI

struct ModelOption: Identifiable, Hashable {
    let id: String
    let title: String
    let isRecommended: Bool
}

struct SettingsInstalledModel: Identifiable, Hashable {
    let id: String
    let fileName: String
    let displayName: String
    let sizeText: String
    let isManaged: Bool
    let isActive: Bool
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
    var installedModels: [SettingsInstalledModel]
    var modelManagementStatus: String
    var isManagingModels: Bool

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
        isUpdatingModels: false,
        installedModels: [],
        modelManagementStatus: "Готово",
        isManagingModels: false
    )
}

struct SettingsActions {
    var snapshot: () -> SettingsSnapshot
    var setLaunchAtLogin: (Bool) -> Void
    var setHotkey: (String) -> Void
    var setModel: (String) -> Void
    var checkUpdates: (@escaping (SettingsSnapshot) -> Void) -> Void
    var updateModels: (@escaping (SettingsSnapshot) -> Void) -> Void
    var addModelFromURL: (String, @escaping (SettingsSnapshot) -> Void) -> Void
    var deleteModel: (String, @escaping (SettingsSnapshot) -> Void) -> Void
    var openModelsFolder: () -> Void
    var resetStats: () -> Void

    static let mock = SettingsActions(
        snapshot: { .mock },
        setLaunchAtLogin: { _ in },
        setHotkey: { _ in },
        setModel: { _ in },
        checkUpdates: { completion in completion(.mock) },
        updateModels: { completion in completion(.mock) },
        addModelFromURL: { _, completion in completion(.mock) },
        deleteModel: { _, completion in completion(.mock) },
        openModelsFolder: {},
        resetStats: {}
    )
}

final class SettingsViewModel: ObservableObject {
    @Published private(set) var snapshot: SettingsSnapshot

    let hotkeyOptions: [HotkeyMode]

    private let actions: SettingsActions

    init(
        actions: SettingsActions = .mock,
        hotkeyOptions: [HotkeyMode] = HotkeyMode.allCases
    ) {
        self.actions = actions
        self.hotkeyOptions = hotkeyOptions
        self.snapshot = actions.snapshot()
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

    func resetStats() {
        actions.resetStats()
        reload()
    }
}

private enum SettingsTab: Hashable {
    case general
    case models
    case stats
}

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    @AppStorage("voice_input_launch_at_login") private var launchAtLogin = false
    @AppStorage("voice_input_hotkey_mode") private var hotkey = HotkeyMode.shiftOption.rawValue
    @AppStorage("voice_input_transcribe_model") private var selectedModelID = TranscribeModel.mediumQ5.rawValue

    @State private var selectedTab: SettingsTab = .general
    @StateObject private var modelManager: ModelManager

    private let pickerWidth: CGFloat = 280
    private let controlsColumnWidth: CGFloat = 380

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        _modelManager = StateObject(wrappedValue: ModelManager(onActiveModelChanged: { modelID in
            viewModel.applyModel(modelID)
        }))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem {
                    Label("Общие", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            ModelsSettingsView(manager: modelManager)
                .tabItem {
                    Label("Модели", systemImage: "cpu")
                }
                .tag(SettingsTab.models)

            statsTab
                .tabItem {
                    Label("Статистика", systemImage: "chart.bar")
                }
                .tag(SettingsTab.stats)
        }
        .frame(minWidth: 860, minHeight: 680)
        .onAppear {
            viewModel.reload()
            syncStorageFromSnapshot()
            modelManager.refresh()
            modelManager.syncExternalSelection(viewModel.snapshot.selectedModelID)
        }
        .onReceive(viewModel.$snapshot) { _ in
            syncStorageFromSnapshot()
            modelManager.syncExternalSelection(viewModel.snapshot.selectedModelID)
        }
    }

    private var generalTab: some View {
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
            }

            Section("Текущая модель") {
                HStack {
                    Text("Активная")
                    Spacer()
                    Text(modelManager.activeModelDescriptor?.fileName ?? "Не выбрана")
                        .foregroundStyle(.secondary)
                }

                Text("Установлено: \(modelManager.installedModelIDs.count) модели")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }

    private var statsTab: some View {
        Form {
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
